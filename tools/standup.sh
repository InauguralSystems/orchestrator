#!/usr/bin/env bash
# standup.sh — what moved across the company. Read-only.
# Usage: tools/standup.sh [days]   (default 1)
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1

ROOT="$(orch_expand "$(orch_get root)")"
ORG="$(orch_get github_org)"
DAYS="${1:-1}"
LOCAL_ONLY="${STANDUP_LOCAL:-0}"

echo "# Standup — last ${DAYS}d ($(date +%F))"
echo

any=0
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  repo="${entry%%:*}"
  dir="$ROOT/$repo"
  [ -d "$dir/.git" ] || continue
  log="$(git -C "$dir" log --oneline --since="${DAYS} days ago" --format='  - %s' 2>/dev/null)"
  n="$(printf '%s' "$log" | grep -c . || true)"
  [ "$n" -eq 0 ] && continue
  any=1
  echo "## $repo ($n commits)"
  echo "$log" | head -20
  [ "$n" -gt 20 ] && echo "  … and $((n-20)) more"
  echo
done <<< "$(orch_repos)"
[ "$any" -eq 0 ] && echo "_No commits in the last ${DAYS}d._"

if [ "$LOCAL_ONLY" -eq 0 ] && command -v gh >/dev/null 2>&1 && [ -n "$ORG" ]; then
  echo "## Open PRs across the company"
  found=0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    repo="${entry%%:*}"
    prs="$(gh pr list -R "$ORG/$repo" --json number,title,author \
      --jq '.[] | "  - #\(.number) \(.title) (@\(.author.login))"' 2>/dev/null)"
    [ -n "$prs" ] && { echo "### $repo"; echo "$prs"; found=1; }
  done <<< "$(orch_repos)"
  [ "$found" -eq 0 ] && echo "_No open PRs._"
fi
