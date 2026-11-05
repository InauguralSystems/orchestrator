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

# Publishing to a branch (`reports_branch:`): the branch holds the only durable
# copy of the files that keep history, so bring the local ones up to date
# BEFORE health appends today's row. A fresh clone, or a pull that deleted the
# formerly tracked copies, would otherwise start a new history.csv and publish
# one row over the whole trend. history.csv always keeps history;
# `reports_cumulative:` names any others (they are published too).
reports_branch="$(orch_get reports_branch)"
keep=(-k reports/history.csv)
while IFS= read -r f; do [ -n "$f" ] && keep+=(-k "$f"); done < <(_orch_list reports_cumulative)
if [ -n "$reports_branch" ]; then
  PUBLISH_REFUSE="$(orch_get protected_branches)" \
  bash "$PRODUCT/tools/publish_reports.sh" --restore "${keep[@]}" "$reports_branch" 2>&1 \
    || echo "ATTENTION: could not bring the history files up to date from '$reports_branch' — see the line above"
fi

bash "$PRODUCT/tools/health.sh" > /dev/null 2>&1
health_rc=$?
bash "$PRODUCT/tools/standup.sh" 1 > reports/standup_latest.md 2>/dev/null
bash "$PRODUCT/tools/dashboard.sh" > /dev/null 2>&1

state=$(tail -1 reports/history.csv 2>/dev/null | awk -F, '{print $NF}')
echo "health: ${state:-?} (exit $health_rc); reports updated"

if [ -n "$reports_branch" ]; then
  # Publish the generated reports to a branch of their own. This is the mode
  # for a company repo whose default branch is protected: a cron job cannot
  # land there without an admin bypass, and the checkout is usually on a PR
  # branch anyway. publish_reports.sh touches neither the checkout nor its
  # index, refuses the default branch and every `protected_branches:` name, and
  # refuses to publish a history file that lost published lines.
  # `reports_publish:` in the config adds snapshot files (under reports/).
  files=(reports/latest.md reports/standup_latest.md reports/dashboard.html)
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(_orch_list reports_publish)
  PUBLISH_REFUSE="$(orch_get protected_branches)" \
  bash "$PRODUCT/tools/publish_reports.sh" -m "sweep: daily report $(date +%F) — ${state:-?}" \
      "${keep[@]}" "$reports_branch" "${files[@]}" 2>&1 \
    || echo "ATTENTION: reports were NOT published to '$reports_branch' — see the line above"
else
  # Default: commit only report artifacts on the current branch and push it.
  # Never sweeps up unrelated working changes. Under branch protection set
  # `reports_branch:` instead; this path then pushes to whatever branch the
  # checkout happens to be on.
  git add reports/ >/dev/null 2>&1
  if ! git diff --cached --quiet -- reports/ 2>/dev/null; then
    git commit -q -m "sweep: daily report $(date +%F) — ${state:-?}" -- reports/ 2>/dev/null
    git push -q 2>/dev/null || echo "push failed (offline?) — will ride along with the next push"
  fi
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
