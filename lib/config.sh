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
# that never ran the child's sweep has nothing on disk. There can be two
# copies, the checkout's files and the branch's (extracted under TMP), and the
# newer one must be read: the older one can say GREEN while the newer says RED.
#
# Which branch tip: the local branch and origin's can differ (a publish queued
# here, or one fetched from elsewhere). The one that descends from the other is
# newer. Commit times do not decide that; two publishes in one second tie. Only
# when the tips have diverged does the later commit time win, origin on a tie.
#
# Which copy, checkout or branch: history.csv only ever grows, so it orders
# them exactly. If one copy's history is the start of the other's, the longer
# one has seen more sweeps and is newer (the same history: the branch, the
# published copy). Dates cannot do this; two sweeps in one day tie.
# If neither history is the start of the other (two machines, unrelated
# files), the later last date wins, and when the dates tie too the copies
# cannot be ordered: the worse verdict is read, RED over YELLOW over GREEN,
# because a known failure is never hidden.
_orch_is_prefix() { # the bytes of file A are the start of file B
  local n; n="$(wc -c < "$1" | tr -d ' ')"
  [ "$n" -eq 0 ] && return 0
  [ "$n" -le "$(wc -c < "$2" | tr -d ' ')" ] && cmp -s -n "$n" "$1" "$2"
}
_orch_verdict_rank() { # FILE -> 3 RED, 2 YELLOW, 1 GREEN, 0 none
  case "$(grep -oE 'GREEN|YELLOW|RED' "$1" 2>/dev/null | tail -1)" in RED) echo 3;; YELLOW) echo 2;; GREEN) echo 1;; *) echo 0;; esac
}
# _orch_subgit ARGS — read-only git in the subsidiary's checkout ($dir of the caller),
# without running anything its config names (the same care health.sh takes).
_orch_subgit() { git -C "$dir" -c core.fsmonitor= -c core.hooksPath=/dev/null --no-optional-locks "$@"; }
orch_sub_reports() {
  local dir="$1" tmp="$2" b="" sha="" l r out f disk d_disk d_br
  disk="$dir/reports"
  [ -f "$dir/orchestrator.yaml" ] && b="$(ORCH_CONFIG="$dir/orchestrator.yaml"; orch_get reports_branch)"
  [ -n "$b" ] || b="$(orch_get subsidiary_reports_branch)"
  if [ -z "$b" ] || ! git check-ref-format --branch "$b" >/dev/null 2>&1; then printf '%s\n' "$disk"; return; fi
  l="$(_orch_subgit rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null)"
  r="$(_orch_subgit rev-parse -q --verify "refs/remotes/origin/$b^{commit}" 2>/dev/null)"
  if   [ -z "$l" ]; then sha="$r"
  elif [ -z "$r" ] || [ "$l" = "$r" ]; then sha="$l"
  elif _orch_subgit merge-base --is-ancestor "$l" "$r" 2>/dev/null; then sha="$r"
  elif _orch_subgit merge-base --is-ancestor "$r" "$l" 2>/dev/null; then sha="$l"
  elif [ "$(_orch_subgit log -1 --format=%ct "$l" 2>/dev/null || echo 0)" -gt "$(_orch_subgit log -1 --format=%ct "$r" 2>/dev/null || echo 0)" ]; then sha="$l"
  else sha="$r"; fi
  if [ -z "$sha" ] || ! _orch_subgit cat-file -e "$sha:reports/latest.md" 2>/dev/null; then printf '%s\n' "$disk"; return; fi
  out="$tmp/$(basename "$dir")"; rm -rf "$out"; mkdir -p "$out" || { printf '%s\n' "$disk"; return; }
  for f in latest.md history.csv standup_latest.md; do
    _orch_subgit cat-file -e "$sha:reports/$f" 2>/dev/null && _orch_subgit cat-file blob "$sha:reports/$f" > "$out/$f"
  done
  [ -f "$disk/latest.md" ] || { printf '%s\n' "$out"; return; }
  # Both copies exist. Order them by history.
  if [ -f "$disk/history.csv" ] && [ -f "$out/history.csv" ]; then
    if _orch_is_prefix "$disk/history.csv" "$out/history.csv"; then printf '%s\n' "$out"; return; fi   # same, or branch longer
    if _orch_is_prefix "$out/history.csv" "$disk/history.csv"; then printf '%s\n' "$disk"; return; fi  # checkout longer
  elif [ -f "$out/history.csv" ]; then printf '%s\n' "$out"; return
  elif [ -f "$disk/history.csv" ]; then printf '%s\n' "$disk"; return
  fi
  d_disk="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$disk/history.csv" 2>/dev/null | tail -1)"
  d_br="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$out/history.csv" 2>/dev/null | tail -1)"
  if   [ "$d_disk" \> "$d_br" ]; then printf '%s\n' "$disk"     # ISO dates order as strings
  elif [ "$d_disk" \< "$d_br" ]; then printf '%s\n' "$out"
  elif [ "$(_orch_verdict_rank "$disk/latest.md")" -gt "$(_orch_verdict_rank "$out/latest.md")" ]; then printf '%s\n' "$disk"
  else printf '%s\n' "$out"; fi
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
