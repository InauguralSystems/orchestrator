#!/usr/bin/env bash
# health.sh — company health scorecard, driven entirely by orchestrator.yaml.
# Read-only: git state + GitHub API. Never builds, tests, or mutates repos.
# Usage: tools/health.sh [--local]   (--local skips all gh/network calls)
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1

LOCAL_ONLY=0
[ "${1:-}" = "--local" ] && LOCAL_ONLY=1

ROOT="$(orch_expand "$(orch_get root)")"
ORG="$(orch_get github_org)"
COMPANY="$(orch_get company Company)"
LIVE_SKILLS="$(orch_expand "$(orch_get live_skills "$HOME/.claude/skills")")"
SKILLS_DIR="$ORCH_HOME/$(orch_get skills_dir skills)"

mkdir -p "$ORCH_HOME/reports"
REPORT="$ORCH_HOME/reports/latest.md"
HISTORY="$ORCH_HOME/reports/history.csv"

# Resolve the GitHub owner for a repo: explicit github_org, else the remote.
gh_owner() {
  if [ -n "$ORG" ]; then printf '%s\n' "$ORG"; return; fi
  git -C "$ROOT/$1" remote get-url origin 2>/dev/null \
    | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#' | head -1
}
ci_of() { # latest workflow-run conclusion, or "-"
  local o; o="$(gh_owner "$1")"; [ -n "$o" ] || { echo "?"; return; }
  gh run list -R "$o/$1" -L 1 --json conclusion \
    --jq 'if length==0 then "-" else (.[0].conclusion // "running") end' 2>/dev/null || echo "?"
}
open_of() { # open issues+PRs
  local o; o="$(gh_owner "$1")"; [ -n "$o" ] || { echo "?"; return; }
  gh api "repos/$o/$1" --jq '.open_issues_count' 2>/dev/null || echo "?"
}

TODAY="$(date +%F)"
{
  echo "# ${COMPANY} health — $TODAY"
  echo
  echo "| Repo | Cat | CI | Dirty | ±origin | 7d | 30d | Open | Status |"
  echo "|---|---|---|---|---|---|---|---|---|"
} > "$REPORT"

ok=0; warn=0; fail=0

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  repo="${entry%%:*}"; cat="${entry##*:}"
  dir="$ROOT/$repo"
  status="OK"; why=""

  if [ ! -d "$dir/.git" ]; then
    dirty="-"; ab="-"; c7="-"; c30="-"
    [ "$cat" = "parked" ] || { status="WARN"; why="not cloned"; }
  else
    dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      ab=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null \
           | awk '{printf "-%s/+%s", $1, $2}')
    else ab="?"; fi
    c7=$(git -C "$dir" log --oneline --since='7 days ago' 2>/dev/null | wc -l | tr -d ' ')
    c30=$(git -C "$dir" log --oneline --since='30 days ago' 2>/dev/null | wc -l | tr -d ' ')
    [ "$dirty" -gt 0 ] && { status="WARN"; why="dirty tree"; }
    [ "$ab" != "-0/+0" ] && [ "$ab" != "?" ] && { status="WARN"; why="${why:+$why; }out of sync w/ origin"; }
    if [ "$cat" != "parked" ] && [ "$cat" != "sibling" ] && [ "$c30" -eq 0 ]; then
      status="WARN"; why="${why:+$why; }no motion 30d"
    fi
  fi

  ci="skip"; open="skip"
  if [ "$LOCAL_ONLY" -eq 0 ] && command -v gh >/dev/null 2>&1; then
    ci="$(ci_of "$repo")"; open="$(open_of "$repo")"
    if [ "$ci" = "failure" ] && [ "$cat" != "parked" ]; then
      status="FAIL"; why="${why:+$why; }CI red"
    fi
  fi

  if [ "$cat" = "parked" ]; then
    status="parked"
    [ "${c30:-0}" != "-" ] && [ "${c30:-0}" -gt 0 ] 2>/dev/null && { status="parked!"; why="motion in a parked repo"; }
  else
    case "$status" in OK) ok=$((ok+1));; WARN) warn=$((warn+1));; FAIL) fail=$((fail+1));; esac
  fi

  echo "| $repo | $cat | $ci | $dirty | $ab | $c7 | $c30 | $open | **$status**${why:+ — $why} |" >> "$REPORT"
done <<< "$(orch_repos)"

# Skills drift: committed copy must match the live employees.
skills_drift=0
if [ -d "$SKILLS_DIR" ] && [ -d "$LIVE_SKILLS" ]; then
  skills_drift=$(diff -rq "$LIVE_SKILLS" "$SKILLS_DIR" 2>&1 | grep -vc '^Common' || true)
  [ "$skills_drift" -gt 0 ] && warn=$((warn+1))
fi

if [ "$fail" -gt 0 ]; then state="RED"
elif [ "$warn" -gt 2 ]; then state="YELLOW"
else state="GREEN"; fi

{
  echo
  echo "## Summary"
  echo
  echo "- Active repos: OK=$ok WARN=$warn FAIL=$fail → **$state**"
  if [ "$skills_drift" -gt 0 ]; then
    echo "- Skills drift: $skills_drift entries differ between live and committed — run 'orchestrator sync'"
  else
    echo "- Skills: live tree and committed copy in sync"
  fi
  [ "$LOCAL_ONLY" -eq 1 ] && echo "- (network signals skipped: --local)"
} >> "$REPORT"

[ -f "$HISTORY" ] || echo "date,ok,warn,fail,state" > "$HISTORY"
echo "$TODAY,$ok,$warn,$fail,$state" >> "$HISTORY"

cat "$REPORT"
[ "$state" = "RED" ] && exit 1
exit 0
