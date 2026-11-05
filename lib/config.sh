#!/usr/bin/env bash
# lib/config.sh — Orchestrator config loader. Sourced by every tool.
#
# Finds the active company config (orchestrator.yaml), then exposes:
#   ORCH_HOME          dir containing the config (the company repo)
#   ORCH_CONFIG        path to the resolved config file
#   orch_get KEY [def] read a scalar
#   orch_repos         emit one "name:category" per line
#   orch_vetoes        emit one veto per line
#   orch_expand PATH   expand a leading ~ to $HOME
#
# Config resolution order (first hit wins):
#   $ORCH_CONFIG env var → ./orchestrator.yaml → $ORCH_HOME/orchestrator.yaml
#
# The parser is deliberately pure awk/bash — no yq/python dependency — and
# supports exactly the flat schema documented in orchestrator.example.yaml.
set -u

orch_expand() { case "$1" in "~"|"~/"*) printf '%s\n' "${HOME}${1#\~}";; *) printf '%s\n' "$1";; esac; }

_orch_find_config() {
  if [ -n "${ORCH_CONFIG:-}" ] && [ -f "${ORCH_CONFIG}" ]; then printf '%s\n' "$ORCH_CONFIG"; return 0; fi
  if [ -f "./orchestrator.yaml" ]; then printf '%s\n' "$(pwd)/orchestrator.yaml"; return 0; fi
  if [ -n "${ORCH_HOME:-}" ] && [ -f "${ORCH_HOME}/orchestrator.yaml" ]; then printf '%s\n' "${ORCH_HOME}/orchestrator.yaml"; return 0; fi
  return 1
}

ORCH_CONFIG="$(_orch_find_config)" || {
  echo "orchestrator: no orchestrator.yaml found (looked at \$ORCH_CONFIG, ./, \$ORCH_HOME)." >&2
  echo "  Run 'orchestrator init' in your company repo to create one." >&2
  return 1 2>/dev/null || exit 1
}
ORCH_HOME="$(cd "$(dirname "$ORCH_CONFIG")" && pwd)"
export ORCH_CONFIG ORCH_HOME

# orch_get KEY [default] — read a top-level scalar "key: value"
orch_get() {
  local key="$1" def="${2:-}" val
  val="$(awk -v k="$key" '
    /^[A-Za-z0-9_]+:/ {
      ky=$0; sub(/:.*/,"",ky)
      if (ky==k) { v=$0; sub(/^[^:]*:[ \t]*/,"",v); sub(/[ \t]+#.*/,"",v); sub(/^#.*/,"",v); print v; exit }
      # ^ strip an inline comment (whitespace-preceded), then a comment that is
      #   the WHOLE value: an empty scalar + comment leaves "#..." with no
      #   leading space after the key is removed, which the first sub misses (G2).
    }' "$ORCH_CONFIG")"
  [ -n "$val" ] && printf '%s\n' "$val" || printf '%s\n' "$def"
}

# _orch_list SECTION — emit each "- item" under a top-level "section:" block
_orch_list() {
  awk -v s="$1" '
    $0 ~ "^"s":[ \t]*(#.*)?$" { inb=1; next }
    # ^ the header may carry a comment ("reports_publish:   # optional"); a
    #   header the parser did not recognise used to drop the whole list silently.
    inb && /^[A-Za-z0-9_]+:/ { inb=0 }
    inb && /^[ \t]*-[ \t]*/ { l=$0; sub(/^[ \t]*-[ \t]*/,"",l); sub(/[ \t]+#.*/,"",l); sub(/^#.*/,"",l); sub(/[ \t]+$/,"",l); if (l!="") print l }
    # ^ list items strip inline comments too (G1): the same whitespace-preceded
    #   rule as scalars, plus a comment-only "- # ..." line drops to empty.
  ' "$ORCH_CONFIG"
}

# orch_sub_reports DIR TMP — the directory to read a subsidiary's reports from.
# A child that publishes its reports to a branch (`reports_branch:` in ITS
# orchestrator.yaml, or `subsidiary_reports_branch:` in ours for a child that
# runs its own tooling) keeps no report files on its default branch, so a clone
# that never ran the child's sweep has nothing on disk. Read the newer of the
# two copies: the checkout's files, or the branch (local or origin, whichever
# tip is newer) extracted under TMP. "Newer" is the last date in history.csv,
# the same clock the staleness guard uses; a tie goes to the checkout.
orch_sub_reports() {
  local dir="$1" tmp="$2" b="" sha out f d_disk d_br
  [ -f "$dir/orchestrator.yaml" ] && b="$(ORCH_CONFIG="$dir/orchestrator.yaml"; orch_get reports_branch)"
  [ -n "$b" ] || b="$(orch_get subsidiary_reports_branch)"
  if [ -z "$b" ] || ! git check-ref-format --branch "$b" >/dev/null 2>&1; then printf '%s\n' "$dir/reports"; return; fi
  sha="$(git -C "$dir" -c core.fsmonitor= -c core.hooksPath=/dev/null --no-optional-locks for-each-ref \
           --sort=-committerdate --count=1 --format='%(objectname)' "refs/heads/$b" "refs/remotes/origin/$b" 2>/dev/null)"
  if [ -z "$sha" ] || ! git -C "$dir" cat-file -e "$sha:reports/latest.md" 2>/dev/null; then printf '%s\n' "$dir/reports"; return; fi
  out="$tmp/$(basename "$dir")"; mkdir -p "$out" || { printf '%s\n' "$dir/reports"; return; }
  for f in latest.md history.csv standup_latest.md; do
    git -C "$dir" cat-file -e "$sha:reports/$f" 2>/dev/null && git -C "$dir" cat-file blob "$sha:reports/$f" > "$out/$f"
  done
  if [ -f "$dir/reports/latest.md" ]; then
    d_disk="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$dir/reports/history.csv" 2>/dev/null | tail -1)"
    d_br="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$out/history.csv" 2>/dev/null | tail -1)"
    # ISO dates order as strings. Checkout wins unless the branch is strictly newer.
    if [ -z "$d_br" ] || { [ -n "$d_disk" ] && [ ! "$d_disk" \< "$d_br" ]; }; then printf '%s\n' "$dir/reports"; return; fi
  fi
  printf '%s\n' "$out"
}

orch_repos()  { _orch_list repos; }   # each line: name:category
orch_vetoes() { _orch_list vetoes; }

# orch_ghslug NAME — the GitHub "owner/repo" slug for a portfolio repo, derived
# from its local checkout's origin remote so a directory name that differs from
# the GitHub repo name resolves correctly (e.g. dir "dot-github" -> repo
# ".github", which "$github_org/NAME" would silently 404 on). Falls back to
# "$github_org/NAME", then bare "NAME", when there is no usable remote.
orch_ghslug() {
  local name="$1" root url slug
  root="$(orch_expand "$(orch_get root)")"
  url="$(git -C "$root/$name" remote get-url origin 2>/dev/null)"
  if [ -n "$url" ]; then
    slug="$(printf '%s' "$url" | sed -E 's#\.git$##; s#^.*[:/]([^:/]+/[^:/]+)$#\1#')"
    case "$slug" in */*) printf '%s\n' "$slug"; return;; esac
  fi
  local org; org="$(orch_get github_org)"
  [ -n "$org" ] && printf '%s\n' "$org/$name" || printf '%s\n' "$name"
}
