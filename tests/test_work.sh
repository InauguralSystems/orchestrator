#!/usr/bin/env bash
# work --dry-run: the autonomous work-session kickoff prompt. These assert the
# LOOP DISCIPLINE is present in the prompt the product hands to Claude — the two
# that matter most are the honest terminal state (no make-work) and escalating
# only the CEO-irreducible decisions.

t_work_dryrun_builds_the_loop() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "reports to the Chief of Staff"      "$out" "Chief of Staff"
  assert_contains "names the router skill (default triage)" "$out" "'triage'"
  assert_contains "runs the workflow rhythm"           "$out" "workflow"
  assert_contains "gates + adversarial review gate landing" "$out" "adversarial review"
  assert_contains "trusts the gate over review"        "$out" "Trust the gate"
  assert_contains "escalates to propose when dry"      "$out" "'propose'"
  assert_contains "surfaces the standing vetoes"       "$out" "No test left red"
}

t_work_has_an_honest_terminal_state() {  # the anti-make-work brake
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "is not a make-work machine"         "$out" "make-work machine"
  assert_contains "zero proposals is a valid outcome"  "$out" "zero proposals"
  assert_contains "refuses to manufacture work"        "$out" "do NOT manufacture"
  assert_contains "wraps and stops when dry"           "$out" "WRAP"
}

t_work_escalates_only_the_irreducible() {  # research collapses HOW, not WHETHER
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "researches before escalating"       "$out" "research the best approach"
  assert_contains "resolves HOW questions itself"      "$out" "HOW question"
  assert_contains "escalates only WHETHER questions"   "$out" "WHETHER questions"
  assert_contains "escalates one rec, never a menu"    "$out" "never a menu"
}

t_work_carries_the_reframe_and_capture_discipline() {  # the loop's smarter behaviors
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "reframes instead of tunneling on a stuck fix" "$out" "REFRAME"
  assert_contains "carries the geometric reframe for heisenbugs"  "$out" "GEOMETRICALLY"
  assert_contains "captures the root-cause WHY, not the patch"    "$out" "ROOT CAUSE"
  assert_contains "proves the why with a failing-then-passing test" "$out" "FAILS without the fix"
  assert_contains "keeps external-memory continuity"              "$out" "CONTINUITY"
  assert_contains "wraps honestly before the hard bound"          "$out" "BOUNDS"
}

t_work_honors_a_custom_chief_of_staff() {  # generic: the router name is configurable
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  printf 'chief_of_staff: head-honcho\n' >> "$co/orchestrator.yaml"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "uses the configured Chief of Staff skill" "$out" "'head-honcho'"
}
