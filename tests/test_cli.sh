#!/usr/bin/env bash
# CLI surface: version, help, unknown command, and the cli-engineer's own bar.

t_version() {
  local out; out="$("$ORCH_BIN" version)"
  assert_contains "version prints name+number" "$out" "orchestrator 0."
}

t_help_lists_subcommands() {
  local out; out="$("$ORCH_BIN" help)"
  assert_contains "help lists init"    "$out" "orchestrator init"
  assert_contains "help lists setup"   "$out" "orchestrator setup"
  assert_contains "help lists health"  "$out" "orchestrator health"
  assert_contains "help lists hire"    "$out" "orchestrator hire"
  assert_contains "help lists propose" "$out" "orchestrator propose"
  assert_missing  "help has no set -u leak" "$out" "set -u"
}

t_unknown_command_fails() {
  assert_fail "unknown command exits nonzero" "$ORCH_BIN" frobnicate
}

t_all_scripts_parse() {  # the orchestrator-cli-engineer mechanical bar
  local f
  for f in "$PRODUCT/orchestrator" "$PRODUCT/lib/config.sh" "$PRODUCT"/tools/*.sh "$PRODUCT"/tests/*.sh; do
    assert_ok "bash -n $(basename "$f")" bash -n "$f"
  done
}
