#!/usr/bin/env bash
# publish_reports.sh — commit generated report files to a dedicated branch and
# push it, without touching the working checkout.
#
# Usage: publish_reports.sh [-C DIR] [-m MESSAGE] BRANCH FILE...
#
# Why this exists. The daily sweep used to commit reports/ on whatever branch
# the company checkout was on and push that. Two things broke it at once when
# the default branch got protection (a pull request and passing checks):
#   - a cron job can land on a protected branch only as an admin bypass, and
#   - every change now needs a PR branch in the same checkout, so the checkout
#     is rarely on the default branch; the sweep then pushed its reports to a
#     merged PR's branch for a week and nothing looked wrong.
# So the generated reports get a branch of their own. Each run makes one commit
# whose tree is exactly the named FILEs as they are on disk, on top of the
# previous run's commit.
#
# What it does not touch: HEAD, the current branch, the index, the working
# tree. It uses a private index, so it works from any branch, with a dirty
# tree, and on files .gitignore excludes.
#
# What it refuses, because each is a way to publish the wrong thing or to the
# wrong place:
#   - the default branch (main, master, whatever the remote says its default
#     is, and any name in $PUBLISH_REFUSE); if the default cannot be learned
#     from the remote or from a cached origin/HEAD, that is a refusal, not a pass
#   - a BRANCH that other branches use as a prefix (`reports` when
#     `reports/2026-q3` exists): git cannot hold both
#   - an existing BRANCH whose tip this script did not make (the tip commit
#     carries a "Published-By:" trailer): a commit here replaces the whole
#     tree, so pointing it at a code branch would empty that branch
#   - a FILE outside reports/, or one reached through a symlink: a link in
#     reports/ would otherwise publish whatever it points at
# FILEs are relative to the repository root.
#
# Exit 0  published, or nothing changed and nothing was waiting to be pushed
#      2  usage, a FILE that is not a plain file under reports/, or none of the
#         FILEs exist (zero files is never a pass)
#      3  refused: BRANCH is a default/protected branch, is checked out here,
#         or exists and is not a reports branch
#      4  the remote branch has commits this clone does not; never force-pushes
#      5  committed locally but the push failed; the next run pushes the queue
set -u

REMOTE="${PUBLISH_REMOTE:-origin}"
DIR="."; MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -C) DIR="$2"; shift 2;;
    -m) MSG="$2"; shift 2;;
    --) shift; break;;
    -*) echo "publish_reports: unknown option $1" >&2; exit 2;;
    *)  break;;
  esac
done
[ $# -ge 2 ] || { echo "usage: publish_reports.sh [-C DIR] [-m MESSAGE] BRANCH FILE..." >&2; exit 2; }
BRANCH="$1"; shift

cd "$DIR" || exit 2
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "publish_reports: $DIR is not inside a git working tree" >&2; exit 2; }
cd "$TOP" || exit 2
TOP="$(pwd -P)"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || { echo "publish_reports: '$BRANCH' is not a branch name" >&2; exit 2; }

# Never the default branch. Ask the remote what its default is; fall back to
# the cached origin/HEAD when it cannot be reached. Knowing neither is a
# refusal: a guard that passes when it could not look is not a guard.
default="$(git ls-remote --symref "$REMOTE" HEAD 2>/dev/null | awk '$1=="ref:" && $3=="HEAD" {sub("^refs/heads/","",$2); print $2; exit}')"
if [ -z "$default" ]; then
  default="$(git symbolic-ref -q --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)"; default="${default#"$REMOTE"/}"
fi
if [ -z "$default" ]; then
  echo "publish_reports: refusing — cannot learn $REMOTE's default branch (unreachable, and no cached $REMOTE/HEAD), so cannot rule out that '$BRANCH' is it" >&2
  exit 3
fi
for refused in main master "$default" ${PUBLISH_REFUSE:-}; do
  if [ "$BRANCH" = "$refused" ]; then
    echo "publish_reports: refusing to publish to '$BRANCH' (a default or protected branch); reports go to a branch of their own" >&2
    exit 3
  fi
done
# git cannot hold both `reports` and `reports/2026-q3`: a branch name is a path.
# Say so here; the raw error ("cannot lock ref") comes later and explains nothing.
clash="$( { git for-each-ref --format='%(refname:short)' "refs/heads/$BRANCH/"
            git ls-remote --heads "$REMOTE" "refs/heads/$BRANCH/*" 2>/dev/null | sed 's#^.*refs/heads/##'; } | sort -u | head -3 | tr '\n' ' ')"
if [ -n "$clash" ]; then
  echo "publish_reports: refusing — branches already exist under '$BRANCH/' (${clash% }), so a branch named '$BRANCH' cannot be created. Pick a name nothing uses as a prefix." >&2
  exit 3
fi
# update-ref on a checked-out branch would leave that working tree behind it.
if [ "$(git branch --show-current 2>/dev/null)" = "$BRANCH" ] ||
   git worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$BRANCH"; then
  echo "publish_reports: '$BRANCH' is checked out in a working tree; refusing to move it underneath" >&2
  exit 3
fi

LOCAL="refs/heads/$BRANCH"
TRACK="refs/remotes/$REMOTE/$BRANCH"

# Where the remote is. A failed fetch (offline) is not an error yet: the commit
# is still made and queued, and the push below reports the failure.
fetched=0
if git fetch -q "$REMOTE" "+refs/heads/$BRANCH:$TRACK" 2>/dev/null; then fetched=1; fi
remote_tip="$(git rev-parse -q --verify "$TRACK^{commit}" 2>/dev/null || true)"
if [ "$fetched" -eq 0 ] && [ -n "$remote_tip" ]; then
  # The fetch failed but a tracking ref exists. If the remote can be reached
  # and has no such branch, the tracking ref is a leftover (the branch was
  # deleted); drop it so the first publish does not look like a divergence.
  git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1
  if [ $? -eq 2 ]; then git update-ref -d "$TRACK"; remote_tip=""; fi
fi
local_tip="$(git rev-parse -q --verify "$LOCAL^{commit}" 2>/dev/null || true)"

parent="$local_tip"
if [ -n "$remote_tip" ]; then
  if [ -z "$local_tip" ] || git merge-base --is-ancestor "$local_tip" "$remote_tip"; then
    parent="$remote_tip"            # remote is at or ahead of us: build on it
  elif ! git merge-base --is-ancestor "$remote_tip" "$local_tip"; then
    echo "publish_reports: FAILED — $REMOTE/$BRANCH and the local $BRANCH have diverged ($(git rev-parse --short "$remote_tip") vs $(git rev-parse --short "$local_tip")); not forcing. Reconcile by hand." >&2
    exit 4
  fi
fi

# An existing branch must be one this script made. The new commit's tree is
# only the FILEs, so building on anything else would wipe that branch's content.
MARK="Published-By: publish_reports.sh"
if [ -n "$parent" ] && ! git log -1 --format=%B "$parent" | grep -qxF "$MARK"; then
  echo "publish_reports: refusing — '$BRANCH' exists and its tip $(git rev-parse --short "$parent") was not made by this script (no '$MARK' trailer); it is not a reports branch" >&2
  exit 3
fi

# The tree: exactly the FILEs that exist, as they are on disk right now.
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_INDEX_FILE="$TMP/index"
git read-tree --empty
n=0
for f in "$@"; do
  case "$f" in
    reports/?*) ;;
    *) echo "publish_reports: '$f' is not under reports/; refusing" >&2; exit 2;;
  esac
  # No symlink anywhere on the path, and no "..": the resolved path must be
  # the literal one. Checked on links that dangle too (-L before -e).
  if [ -L "$f" ] || { [ -e "$f" ] && [ "$(realpath -e -- "$f" 2>/dev/null)" != "$TOP/$f" ]; }; then
    echo "publish_reports: '$f' is, or is reached through, a symlink (or is not a normal path); refusing" >&2
    exit 2
  fi
  if [ -f "$f" ]; then
    blob="$(git hash-object -w -- "$f")" || exit 2
    git update-index --add --cacheinfo "100644,$blob,$f" || exit 2
    n=$((n+1))
  else
    echo "publish_reports: note: $f does not exist; left out"
  fi
done
if [ "$n" -eq 0 ]; then
  echo "publish_reports: FAILED — none of the $# named files exist; nothing to publish" >&2
  exit 2
fi
tree="$(git write-tree)" || exit 2
unset GIT_INDEX_FILE

new="$parent"
if [ -z "$parent" ] || [ "$tree" != "$(git rev-parse "$parent^{tree}")" ]; then
  [ -n "$MSG" ] || MSG="reports: $(date +%F)"
  if [ -n "$parent" ]; then new="$(git commit-tree "$tree" -p "$parent" -m "$MSG" -m "$MARK")"
  else                      new="$(git commit-tree "$tree" -m "$MSG" -m "$MARK")"; fi
  [ -n "$new" ] || { echo "publish_reports: FAILED — could not create the commit (is user.name/user.email set?)" >&2; exit 2; }
fi
if [ "$new" != "$local_tip" ]; then
  git update-ref "$LOCAL" "$new" ${local_tip:+"$local_tip"} || exit 2
fi

if [ "$new" = "$remote_tip" ]; then
  echo "publish_reports: unchanged ($n file(s); $REMOTE/$BRANCH at $(git rev-parse --short "$new"))"
  exit 0
fi
if git push -q "$REMOTE" "$LOCAL:refs/heads/$BRANCH" 2>"$TMP/push.err"; then
  git update-ref "$TRACK" "$new"
  echo "publish_reports: published $(git rev-parse --short "$new") to $REMOTE/$BRANCH ($n file(s))"
  exit 0
fi
if [ -n "$remote_tip" ]; then queued="$(git rev-list --count "$remote_tip..$new")"
else                          queued="$(git rev-list --count "$new")"; fi
echo "publish_reports: PUSH FAILED — $queued commit(s) queued on the local $BRANCH; the next run pushes them. $(head -1 "$TMP/push.err")" >&2
exit 5
