#!/usr/bin/env bash
# tests/run.sh — the Orchestrator regression suite. Runs every t_* function in
# tests/test_*.sh against throwaway fixture companies and prints TAP output.
# Exit 0 iff all tests pass. Usage: tests/run.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PRODUCT="$(cd "$HERE/.." && pwd)"
export PRODUCT ORCH_BIN="$PRODUCT/orchestrator"

# shellcheck source=/dev/null
. "$HERE/lib.sh"
for f in "$HERE"/test_*.sh; do . "$f"; done

home0="$PWD"
for fn in $(compgen -A function | grep '^t_' | sort); do
  "$fn"
  cd "$home0" 2>/dev/null || true
done

echo "1..$TESTS_RUN"
echo "# $((TESTS_RUN - TESTS_FAIL))/$TESTS_RUN passed"
[ "$TESTS_FAIL" -eq 0 ]
