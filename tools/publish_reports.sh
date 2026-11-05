#!/usr/bin/env bash
# publish_reports.sh — commit generated report files to a dedicated branch and
# push it, without touching the working checkout.
#
# Usage: publish_reports.sh [-C DIR] [-m MESSAGE] [-k FILE]... BRANCH [FILE...]
#        publish_reports.sh --restore [-C DIR] [-k FILE]... BRANCH [FILE...]
#
# Why this exists. The daily sweep used to commit reports/ on whatever branch
# the company checkout was on and push that. Two things broke it at once when
# the default branch got protection (a pull request and passing checks):
#   - a cron job can land on a protected branch only as an admin bypass, and
#   - every change now needs a PR branch in the same checkout, so the checkout
#     is rarely on the default branch; the sweep then pushed its reports to a
#     merged PR's branch for a week and nothing looked wrong.
# So the generated reports get a branch of their own. Each run makes one commit
# whose tree is exactly the named FILEs, byte for byte as they are on disk (no
# clean filter, no line-ending conversion), on top of the previous run's commit.
#
# What it does not touch: HEAD, the current branch, the index, the working
# tree. It uses a private index, so it works from any branch, with a dirty
# tree, and on files .gitignore excludes.
#
# Files that keep history (-k). A file like history.csv only ever grows, and
# once the report files are untracked the branch holds the only durable copy.
# A fresh clone, or a pull that deletes the formerly tracked copies, leaves the
# checkout with no history; the generator then starts a new file, and a publish
# of that would replace the whole trend with one row. Two defences:
#   --restore   run BEFORE the generators. Brings each named file up to date
#               with the published copy: writes it when the local one is
#               missing or empty, and otherwise puts back the published lines
#               the local copy lacks, keeping local lines the branch has not
#               seen. Snapshot files (latest.md) do not need it.
#   -k FILE     in a publish: FILE is published like any other, but the run is
#               refused (exit 6) if the published copy is not a prefix of the
#               local one, that is, if publishing would drop published lines.
#               $PUBLISH_ALLOW_REWRITE=1 lifts this for a deliberate trim.
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
#     reports/ would otherwise publish whatever it points at (and --restore
#     would write through it)
# FILEs are relative to the repository root.
#
# Exit 0  published, or nothing changed and nothing was waiting to be pushed;
#         --restore: every named file is up to date with the published copy
#      2  usage, a FILE that is not a plain file under reports/, or none of the
#         FILEs exist (zero files is never a pass)
#      3  refused: BRANCH is a default/protected branch, is checked out here,
#         or exists and is not a reports branch
#      4  the remote branch has commits this clone does not; never force-pushes
#      5  committed locally but the push failed; the next run pushes the queue.
#         (With -k files, no copy of BRANCH and no remote: nothing is committed.)
#         --restore: the remote could not be reached, so the files are only as
#         current as the last copy this clone saw
#      6  refused: a -k FILE would lose published lines
set -u

REMOTE="${PUBLISH_REMOTE:-origin}"
DIR="."; MSG=""; RESTORE=0; KEEP=()
usage() { echo "usage: publish_reports.sh [--restore] [-C DIR] [-m MESSAGE] [-k FILE]... BRANCH [FILE...]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --restore) RESTORE=1; shift;;
    -C) [ $# -ge 2 ] || usage; DIR="$2"; shift 2;;
    -m) [ $# -ge 2 ] || usage; MSG="$2"; shift 2;;
    -k) [ $# -ge 2 ] || usage; KEEP+=("$2"); shift 2;;
    --) shift; break;;
    -*) echo "publish_reports: unknown option $1" >&2; exit 2;;
    *)  break;;
  esac
done
[ $# -ge 1 ] || usage
BRANCH="$1"; shift
[ $(( $# + ${#KEEP[@]} )) -ge 1 ] || usage
# --restore treats every named file as one that keeps history.
if [ "$RESTORE" -eq 1 ] && [ $# -gt 0 ]; then KEEP+=("$@"); set --; fi

cd "$DIR" || exit 2
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "publish_reports: $DIR is not inside a git working tree" >&2; exit 2; }
cd "$TOP" || exit 2
TOP="$(pwd -P)"
# check_path FILE — under reports/, no "." or ".." or empty component, and no
# symlink at any component (checked on links that dangle too). TOP is the
# physical root and the cwd, so a path that passes names exactly $TOP/FILE.
# Pure shell on purpose: no realpath, which is not a dependency of the product.
check_path() {
  local f="$1" p="" comp rest
  case "$f" in
    reports/?*) ;;
    *) echo "publish_reports: '$f' is not under reports/; refusing" >&2; exit 2;;
  esac
  case "/$f/" in
    *//*|*/./*|*/../*) echo "publish_reports: '$f' is not a normal path ('.', '..' or an empty component); refusing" >&2; exit 2;;
  esac
  rest="$f"
  while [ -n "$rest" ]; do
    comp="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}";; *) rest="";; esac
    p="${p:+$p/}$comp"
    if [ -L "$p" ]; then
      echo "publish_reports: '$f' is, or is reached through, a symlink ('$p'); refusing" >&2
      exit 2
    fi
  done
  if [ -e "$f" ] && [ ! -f "$f" ]; then
    echo "publish_reports: '$f' is not a plain file; refusing" >&2
    exit 2
  fi
}
# is_prefix A B — the bytes of A are the start of B.
is_prefix() {
  local n; n="$(wc -c < "$1" | tr -d ' ')"
  [ "$n" -eq 0 ] && return 0
  [ "$n" -le "$(wc -c < "$2" | tr -d ' ')" ] && cmp -s -n "$n" "$1" "$2"
}

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

# Where the remote is. Three outcomes: fetched, the branch is not there yet, or
# the remote cannot be reached. Unreachable is not an error for a publish: the
# commit is still made and queued, and the push below reports the failure.
fetched=0; unreachable=0
if git fetch -q "$REMOTE" "+refs/heads/$BRANCH:$TRACK" 2>/dev/null; then fetched=1; fi
remote_tip="$(git rev-parse -q --verify "$TRACK^{commit}" 2>/dev/null || true)"
if [ "$fetched" -eq 0 ]; then
  git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1
  case $? in
    2) # Reachable, no such branch. A tracking ref is then a leftover (the branch
       # was deleted); drop it so the first publish does not look like a divergence.
       if [ -n "$remote_tip" ]; then git update-ref -d "$TRACK"; remote_tip=""; fi;;
    *) unreachable=1;;
  esac
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

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

if [ "$RESTORE" -eq 1 ]; then
  # Bring each history-keeping file up to date with the published copy. Nothing
  # is committed or pushed. Output for a file is printed only AFTER that file is
  # written: the sweep log is itself one of these files and receives this output.
  for f in ${KEEP[@]+"${KEEP[@]}"}; do check_path "$f"; done
  if [ -z "$parent" ]; then
    if [ "$unreachable" -eq 1 ]; then
      echo "publish_reports: RESTORE FAILED — $REMOTE cannot be reached and this clone has no copy of '$BRANCH'; local history files were left as they are" >&2
      exit 5
    fi
    echo "publish_reports: nothing published on $REMOTE/$BRANCH yet; nothing to restore"
    exit 0
  fi
  for f in ${KEEP[@]+"${KEEP[@]}"}; do
    git cat-file -e "$parent:$f" 2>/dev/null || continue      # never published
    git cat-file blob "$parent:$f" > "$TMP/pub" || exit 2
    if [ ! -s "$f" ]; then
      mkdir -p "$(dirname "$f")" && cat "$TMP/pub" > "$f" || exit 2
      echo "publish_reports: restored $f from $REMOTE/$BRANCH ($(wc -l < "$TMP/pub" | tr -d ' ') line(s)); the local copy was missing or empty"
    elif ! is_prefix "$TMP/pub" "$f"; then
      # The local copy lacks published lines. Result: every published line, in
      # order, then the local lines the branch has not seen. "Not seen" = what
      # is left of the local copy after dropping its common start with the
      # published one (a CSV header, or history both sides share) and then the
      # longest run that the published copy ends with and the rest starts with.
      awk -v pf="$TMP/pub" '
        BEGIN { while ((getline line < pf) > 0) P[++np] = line }
        { L[++nl] = $0 }
        END {
          c = 0; while (c < np && c < nl && P[c+1] == L[c+1]) c++
          k = nl - c; if (k > np) k = np
          for (; k > 0; k--) {
            ok = 1
            for (i = 1; i <= k; i++) if (P[np-k+i] != L[c+i]) { ok = 0; break }
            if (ok) break
          }
          for (i = 1; i <= np; i++) print P[i]
          for (i = c + k + 1; i <= nl; i++) print L[i]
        }' "$f" > "$TMP/merged" || exit 2
      before="$(wc -l < "$f" | tr -d ' ')"
      cat "$TMP/merged" > "$f" || exit 2          # in place: keeps the inode an appender has open
      echo "publish_reports: reconciled $f with $REMOTE/$BRANCH: $before local line(s) became $(wc -l < "$f" | tr -d ' ') (published lines the local copy lacked were put back)"
    fi
  done
  if [ "$unreachable" -eq 1 ]; then
    echo "publish_reports: RESTORE INCOMPLETE — $REMOTE cannot be reached; history files are only as current as this clone's last copy of '$BRANCH' ($(git rev-parse --short "$parent"))" >&2
    exit 5
  fi
  exit 0
fi

# No copy of the branch anywhere and no way to ask: this may be a clone that
# has simply never fetched it. A first commit made now would be a second,
# unrelated history for files that keep one, and a divergence to sort out by
# hand later. Wait for the remote instead; the next run restores and publishes.
if [ -z "$parent" ] && [ "$unreachable" -eq 1 ] && [ "${#KEEP[@]}" -gt 0 ]; then
  echo "publish_reports: PUSH FAILED — $REMOTE cannot be reached and this clone has no copy of '$BRANCH'; nothing was committed, so that files that keep history are not started over. The next run with $REMOTE reachable publishes." >&2
  exit 5
fi

# The tree: exactly the FILEs that exist, byte for byte as they are on disk
# right now. --no-filters: a clean filter or autocrlf in this clone's config
# must not change what the board says.
export GIT_INDEX_FILE="$TMP/index"
git read-tree --empty
n=0
for f in ${KEEP[@]+"${KEEP[@]}"} "$@"; do
  check_path "$f"
  if [ -f "$f" ]; then
    blob="$(git hash-object -w --no-filters -- "$f")" || exit 2
    git update-index --add --cacheinfo "100644,$blob,$f" || exit 2
    n=$((n+1))
  else
    echo "publish_reports: note: $f does not exist; left out"
  fi
done
if [ "$n" -eq 0 ]; then
  echo "publish_reports: FAILED — none of the $(( $# + ${#KEEP[@]} )) named files exist; nothing to publish" >&2
  exit 2
fi
# A file that keeps history must not lose published lines.
if [ -n "$parent" ] && [ "${PUBLISH_ALLOW_REWRITE:-0}" != "1" ]; then
  for f in ${KEEP[@]+"${KEEP[@]}"}; do
    git cat-file -e "$parent:$f" 2>/dev/null || continue
    git cat-file blob "$parent:$f" > "$TMP/pub" || exit 2
    if [ ! -f "$f" ] || ! is_prefix "$TMP/pub" "$f"; then
      echo "publish_reports: refusing — $f keeps history, and the local copy does not start with the $(wc -l < "$TMP/pub" | tr -d ' ') line(s) already on $REMOTE/$BRANCH; publishing it would drop them. Run with --restore before generating reports. (PUBLISH_ALLOW_REWRITE=1 publishes it anyway.)" >&2
      exit 6
    fi
  done
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
