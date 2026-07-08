#!/usr/bin/env bash
# The safe-autonomy guardrail pack: deny_guard (PreToolUse), stop_gate (Stop), and
# the `work` acceptEdits interlock. These lock the two properties that make an
# autonomous loop survivable: irreversible ops are DENIED, and a turn cannot end
# on red — plus no unsupervised autonomy without the pack installed.

_deny() { printf '%s' "$1" | bash "$(dirname "$ORCH_BIN")/tools/deny_guard.sh" 2>/dev/null; }
_gate() { "$(dirname "$ORCH_BIN")/tools/stop_gate.sh"; }

t_denyguard_blocks_forcepush_and_delete_of_protected() {
  assert_contains "force-push to main is denied" \
    "$(_deny '{"tool_input":{"command":"git push --force origin main"}}')" '"deny"'
  assert_contains "remote delete of master is denied" \
    "$(_deny '{"tool_input":{"command":"git push --delete origin master"}}')" '"deny"'
}

t_denyguard_allows_feature_force_and_normal_push() {
  assert_missing "force-push to a feature branch is allowed" \
    "$(_deny '{"tool_input":{"command":"git push -f origin feature/x"}}')" '"deny"'
  assert_missing "a normal (non-force) push to main is allowed" \
    "$(_deny '{"tool_input":{"command":"git push origin main"}}')" '"deny"'
}

t_denyguard_blocks_rm_of_root_paths() {
  assert_contains "rm -rf /home/<user> is denied" \
    "$(_deny '{"tool_input":{"command":"rm -rf /home/jon"}}')" '"deny"'
  assert_contains "rm -r -f / is denied (split flags)" \
    "$(_deny '{"tool_input":{"command":"rm -r -f /"}}')" '"deny"'
}

t_denyguard_allows_subpaths_and_is_heredoc_exempt() {
  assert_missing "rm -rf of a scratch subdir is allowed" \
    "$(_deny '{"tool_input":{"command":"rm -rf /tmp/scratch"}}')" '"deny"'
  assert_missing "a heredoc that MENTIONS a blocked op is exempt (content-writing)" \
    "$(_deny '{"tool_input":{"command":"cat <<EOF\ngit push --force origin main\nEOF"}}')" '"deny"'
}

t_stopgate_blocks_stop_on_red() {   # dirty tree + failing gate -> exit 2 (keep working)
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  echo change >> "$root/acme/f"                        # uncommitted change
  local co; co="$(mkcompany "$root" "acme:product")"
  printf 'gate: false\n' >> "$co/orchestrator.yaml"    # a gate that always fails
  local rc=0; ( cd "$co" && _gate >/dev/null 2>&1 ) || rc=$?
  assert_ok "red gate on a dirty tree blocks the stop (exit 2)" bash -c "[ $rc -eq 2 ]"
}

t_stopgate_clean_tree_is_free() {   # nothing dirty -> exit 0 without running the gate
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  printf 'gate: false\n' >> "$co/orchestrator.yaml"
  local rc=0; ( cd "$co" && _gate >/dev/null 2>&1 ) || rc=$?
  assert_ok "a clean tree exits 0 even with a failing gate configured" bash -c "[ $rc -eq 0 ]"
}

t_stopgate_is_noop_without_a_gate() {  # no gate: declared -> no-op even when dirty
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  echo change >> "$root/acme/f"
  local co; co="$(mkcompany "$root" "acme:product")"
  local rc=0; ( cd "$co" && _gate >/dev/null 2>&1 ) || rc=$?
  assert_ok "no gate configured -> stop-gate is a no-op (exit 0)" bash -c "[ $rc -eq 0 ]"
}

t_work_refuses_acceptedits_without_the_pack() {  # the interlock
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local home; home="$(mktemp -d)"     # empty HOME: no guardrail hooks anywhere
  local out rc=0
  out="$( cd "$co" && HOME="$home" ORCH_CLAUDE_FLAGS="--permission-mode acceptEdits" "$ORCH_BIN" work 2>&1 )" || rc=$?
  assert_ok "work refuses acceptEdits with no guardrail pack" bash -c "[ $rc -ne 0 ]"
  assert_contains "the refusal names the guardrail pack" "$out" "guardrail"
}
