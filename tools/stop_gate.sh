#!/usr/bin/env bash
# stop_gate.sh — Stop-event guardrail. An autonomous session may not END a turn
# with uncommitted changes that fail the company's gate. The gate command is
# declared in orchestrator.yaml ('gate:'); with none set this is a no-op.
#
# Shape (matches the pattern hq proved in production):
#   - clean tree everywhere  -> exit 0 instantly (conversational stops cost nothing)
#   - dirty + gate passes     -> exit 0
#   - dirty + gate fails      -> exit 2 with the failure on stderr, so the loop
#                                KEEPS WORKING instead of stopping on red
# Escape hatch, consumed per stop (so you can't accidentally leave it off):
#   touch /tmp/orch_stop_gate_skip
set -u
skip=/tmp/orch_stop_gate_skip
[ -f "$skip" ] && { rm -f "$skip"; exit 0; }

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$PRODUCT/lib/config.sh" 2>/dev/null || exit 0
GATE="$(orch_get gate 2>/dev/null || true)"
[ -n "${GATE:-}" ] || exit 0                    # no gate declared -> nothing to enforce
ROOT="$(orch_expand "$(orch_get root 2>/dev/null)" 2>/dev/null)"

# Fire only when something in the portfolio is actually uncommitted.
dirty=0
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  d="$ROOT/${entry%%:*}"
  [ -d "$d/.git" ] || continue
  if ! git -C "$d" diff --quiet 2>/dev/null || ! git -C "$d" diff --cached --quiet 2>/dev/null; then
    dirty=1; break
  fi
done <<< "$(orch_repos 2>/dev/null)"
[ "$dirty" -eq 1 ] || exit 0                     # clean everywhere -> fast exit

# Run the company gate from the company dir. It is the owner's declared "am I OK".
cd "$ORCH_HOME" || exit 0
LOG="$(mktemp)"
if ! eval "$GATE" >"$LOG" 2>&1; then
  { echo "STOP GATE: the company gate failed with uncommitted changes — keep working, don't stop on red."
    echo "  \$ $GATE"
    tail -20 "$LOG"
    echo "(escape hatch, consumed once: touch $skip)"; } >&2
  rm -f "$LOG"
  exit 2
fi
rm -f "$LOG"
exit 0
