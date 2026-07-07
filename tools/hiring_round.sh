#!/usr/bin/env bash
# hiring_round.sh — cron entrypoint for an autonomous hiring round. Runs
# `orchestrator hire` headless and logs the transcript. A round is expensive
# (spawns a recruiter agent per repo), so this runs on its own WEEKLY cadence,
# separate from the daily sweep. For cron:
#   0 9 * * 1 ORCH_CONFIG=/path/orchestrator.yaml \
#     ORCH_CLAUDE_FLAGS="--permission-mode acceptEdits" \
#     /path/to/orchestrator/tools/hiring_round.sh >> /path/reports/hiring.log 2>&1
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1
cd "$ORCH_HOME" || exit 1
mkdir -p reports

echo "=== hiring round $(date '+%F %T') — $(orch_get company Company) ==="
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: 'claude' CLI not found — cannot run an autonomous round." >&2
  exit 0
fi
# ORCH_CLAUDE_FLAGS should carry an autonomy flag (e.g. --permission-mode
# acceptEdits) so the round doesn't block on prompts in a headless context.
bash "$PRODUCT/orchestrator" hire
rc=$?
echo "=== round done $(date '+%F %T') (exit $rc) ==="
exit "$rc"
