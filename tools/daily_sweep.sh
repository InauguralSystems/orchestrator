#!/usr/bin/env bash
# daily_sweep.sh — the scheduled backlog check. Runs health + standup, stores
# the reports, and commits/pushes them so the trend is durable. For cron:
#   23 8 * * * ORCH_CONFIG=/path/to/company/orchestrator.yaml \
#     /path/to/orchestrator/tools/daily_sweep.sh >> /path/to/company/reports/sweep.log 2>&1
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1
cd "$ORCH_HOME" || exit 1
mkdir -p reports

echo "=== sweep $(date '+%F %T') ==="

bash "$PRODUCT/tools/health.sh" > /dev/null 2>&1
health_rc=$?
bash "$PRODUCT/tools/standup.sh" 1 > reports/standup_latest.md 2>/dev/null
bash "$PRODUCT/tools/dashboard.sh" > /dev/null 2>&1

state=$(tail -1 reports/history.csv 2>/dev/null | awk -F, '{print $NF}')
echo "health: ${state:-?} (exit $health_rc); reports updated"

# Commit only report artifacts — never sweep up unrelated working changes.
git add reports/ >/dev/null 2>&1
if ! git diff --cached --quiet -- reports/ 2>/dev/null; then
  git commit -q -m "sweep: daily report $(date +%F) — ${state:-?}" -- reports/ 2>/dev/null
  git push -q 2>/dev/null || echo "push failed (offline?) — will ride along with the next push"
fi

if [ "$health_rc" -ne 0 ]; then
  # RED triage context (#1): a stalled subsidiary is a different alarm from one
  # snapshotted mid-wave. health.sh writes the annotation on the subsidiary row;
  # surface it here so the sweep log line alone says which alarm this is.
  if grep -q 'STALLED:' reports/latest.md 2>/dev/null; then
    echo "ATTENTION: company state RED — subsidiary STALLED; read reports/latest.md"
  elif grep -q 'in motion:' reports/latest.md 2>/dev/null; then
    echo "ATTENTION: company state RED (subsidiary in motion — likely mid-wave); read reports/latest.md"
  else
    echo "ATTENTION: company state RED — read reports/latest.md"
  fi
fi
