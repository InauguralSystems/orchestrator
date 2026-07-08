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
# repo_meta REPO — echo "OPEN PRIVATE": open issues+PRs and the private flag
# (true/false), from one API call. "? ?" when the owner or gh is unavailable.
repo_meta() {
  local o; o="$(gh_owner "$1")"; [ -n "$o" ] || { echo "? ?"; return; }
  gh api "repos/$o/$1" --jq '"\(.open_issues_count) \(.private)"' 2>/dev/null || echo "? ?"
}

# standards_of DIR — the community-standards presence checklist. Echoes
# "PRESENT/5 LICENSE_FLAG" for README, LICENSE, CODE_OF_CONDUCT, CONTRIBUTING,
# SECURITY, read from the committed tree (independent of local checkout state).
# Purely local — a governance signal that works even under --local. NOTE: the
# regexes avoid empty alternations like (a|b|) — BSD/ugrep reject them; use ?.
standards_of() {
  local files n=0 lic=0
  files="$(git -C "$1" ls-tree -r --name-only HEAD 2>/dev/null)" || { echo "0/5 0"; return; }
  printf '%s\n' "$files" | grep -qiE '(^|/)readme(\.md|\.txt)?$'               && n=$((n+1))
  if printf '%s\n' "$files" | grep -qiE '(^|/)(license|licence|copying)(\.md|\.txt)?$'; then n=$((n+1)); lic=1; fi
  printf '%s\n' "$files" | grep -qiE '(^|/|\.github/)code_of_conduct(\.md)?$'  && n=$((n+1))
  printf '%s\n' "$files" | grep -qiE '(^|/|\.github/)contributing(\.md)?$'     && n=$((n+1))
  printf '%s\n' "$files" | grep -qiE '(^|/|\.github/)security(\.md)?$'         && n=$((n+1))
  echo "$n/5 $lic"
}

TODAY="$(date +%F)"
{
  echo "# ${COMPANY} health — $TODAY"
  echo
  echo "| Repo | Cat | CI | Dirty | ±origin | 7d | 30d | Open | Gov | Status |"
  echo "|---|---|---|---|---|---|---|---|---|---|"
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
    if [ "$cat" != "parked" ] && [ "$cat" != "sibling" ] && [ "$cat" != "subsidiary" ] && [ "$c30" -eq 0 ]; then
      status="WARN"; why="${why:+$why; }no motion 30d"
    fi
  fi

  # Governance axis: the community-standards presence checklist (local signal).
  # Show N/5 for every cloned repo. `lic` (LICENSE present) is used below — a
  # missing LICENSE only matters for a PUBLIC repo, so the escalation lives in
  # the network block where visibility is known. The other four standards are
  # surfaced in the count but not yet mandatory (weighting = the next lever).
  if [ -d "$dir/.git" ]; then
    std="$(standards_of "$dir")"; gov="${std% *}"; lic="${std##* }"
  else
    gov="-"; lic=1   # unknown tree: don't manufacture a license warn
  fi

  ci="skip"; open="skip"
  if [ "$LOCAL_ONLY" -eq 0 ] && command -v gh >/dev/null 2>&1; then
    ci="$(ci_of "$repo")"; meta="$(repo_meta "$repo")"; open="${meta%% *}"; priv="${meta##* }"
    if [ "$ci" = "failure" ] && [ "$cat" != "parked" ]; then
      status="FAIL"; why="${why:+$why; }CI red"
    elif [ "$ci" = "-" ] && [ "$cat" != "parked" ] && [ "$cat" != "sibling" ] && [ "$cat" != "subsidiary" ]; then
      # No workflow runs at all: a load-bearing repo with no CI gate must not
      # read the same as one with green CI. "-" (definitively no runs) warns;
      # "?" (owner/gh undetermined) does not. Siblings/subsidiaries are exempt
      # (a subsidiary's CI is its own instrument's concern, not the parent's).
      status="WARN"; why="${why:+$why; }no CI configured"
    fi
    # Missing LICENSE warns only for a PUBLIC repo: a license grants rights to
    # third parties who receive the code, so a private repo (no distribution)
    # correctly has none. Private/unknown visibility → informational count only.
    if [ "$priv" = "false" ] && [ "$lic" = "0" ] && [ "$cat" != "parked" ] && [ "$cat" != "sibling" ] && [ "$cat" != "subsidiary" ]; then
      status="WARN"; why="${why:+$why; }missing LICENSE"
    fi
  fi

  if [ "$cat" = "parked" ]; then
    status="parked"
    [ "${c30:-0}" != "-" ] && [ "${c30:-0}" -gt 0 ] 2>/dev/null && { status="parked!"; why="motion in a parked repo"; }
  elif [ "$cat" = "subsidiary" ]; then
    # A subsidiary is a child company with its OWN health instrument. Roll up its
    # verdict from its reports/latest.md instead of re-scoring its repos here:
    # GREEN->ok, YELLOW->warn, RED->fail (a RED child makes the parent RED).
    # Missing/unreadable report -> WARN. The child's summary line is the only
    # place GREEN|YELLOW|RED appears (row statuses use OK/WARN/FAIL/parked), so
    # the last match on the file is its rolled-up verdict.
    sub_state="$(grep -oE 'GREEN|YELLOW|RED' "$dir/reports/latest.md" 2>/dev/null | tail -1)"
    case "$sub_state" in
      GREEN)  status="GREEN";  why="subsidiary roll-up";          ok=$((ok+1));;
      YELLOW) status="YELLOW"; why="subsidiary roll-up";          warn=$((warn+1));;
      RED)    status="RED";    why="subsidiary roll-up";          fail=$((fail+1));;
      *)      status="WARN";   why="no subsidiary health report"; warn=$((warn+1));;
    esac
  else
    case "$status" in OK) ok=$((ok+1));; WARN) warn=$((warn+1));; FAIL) fail=$((fail+1));; esac
  fi

  echo "| $repo | $cat | $ci | $dirty | $ab | $c7 | $c30 | $open | $gov | **$status**${why:+ — $why} |" >> "$REPORT"
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
