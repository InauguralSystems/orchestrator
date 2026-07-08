#!/usr/bin/env bash
# perf_gate — the n=5 statistical gate. A build gate is binary; a perf claim is
# statistical, so the property that matters is: a "win" whose n=5 distribution
# OVERLAPS the baseline is rejected as not-real-yet, a confirmed non-overlapping
# speedup passes, and a regression fails. One-shots are impossible — it always
# runs n.

_pg() { "$(dirname "$ORCH_BIN")/tools/perf_gate.sh" "$@"; }

# _perfco ROOT — a company whose perf_gate benchmark just prints $ROOT/metric,
# so a test can set the "measurement" by writing that file. Echoes the co dir.
_perfco() {
  local root="$1" co
  co="$(mkcompany "$root" "acme:product")"
  printf 'perf_gate: cat %s/metric\n' "$root" >> "$co/orchestrator.yaml"
  printf '%s\n' "$co"
}

t_perfgate_confirms_a_nonoverlapping_speedup() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(_perfco "$root")"
  echo 100 > "$root/metric"; ( cd "$co" && _pg baseline >/dev/null 2>&1 )
  echo 90  > "$root/metric"
  local out rc=0; out="$( cd "$co" && _pg check 2>&1 )" || rc=$?
  assert_ok "a non-overlapping speedup passes (exit 0)" bash -c "[ $rc -eq 0 ]"
  assert_contains "verdict: confirmed speedup" "$out" "confirmed speedup"
}

t_perfgate_rejects_an_overlapping_claim() {   # the core discipline: overlap != real
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(_perfco "$root")"
  echo 100 > "$root/metric"; ( cd "$co" && _pg baseline >/dev/null 2>&1 )
  echo 100 > "$root/metric"                    # identical distribution -> overlap
  local out rc=0; out="$( cd "$co" && _pg check 2>&1 )" || rc=$?
  assert_ok "overlapping distributions fail (nonzero)" bash -c "[ $rc -ne 0 ]"
  assert_contains "verdict: not real yet" "$out" "OVERLAP"
}

t_perfgate_flags_a_regression() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(_perfco "$root")"
  echo 100 > "$root/metric"; ( cd "$co" && _pg baseline >/dev/null 2>&1 )
  echo 110 > "$root/metric"
  local out rc=0; out="$( cd "$co" && _pg check 2>&1 )" || rc=$?
  assert_ok "a regression fails (nonzero)" bash -c "[ $rc -ne 0 ]"
  assert_contains "verdict: regression" "$out" "REGRESSION"
}

t_perfgate_no_regress_mode_tolerates_overlap() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(_perfco "$root")"
  echo 100 > "$root/metric"; ( cd "$co" && _pg baseline >/dev/null 2>&1 )
  echo 100 > "$root/metric"
  local rc=0; ( cd "$co" && _pg check --no-regress >/dev/null 2>&1 ) || rc=$?
  assert_ok "no-regress mode passes on overlap (exit 0)" bash -c "[ $rc -eq 0 ]"
}

t_perfgate_check_requires_a_baseline() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(_perfco "$root")"
  echo 100 > "$root/metric"
  local out rc=0; out="$( cd "$co" && _pg check 2>&1 )" || rc=$?   # no baseline recorded
  assert_ok "check without a baseline fails" bash -c "[ $rc -ne 0 ]"
  assert_contains "tells you to record a baseline first" "$out" "baseline"
}

t_perfgate_is_noop_without_config() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"   # no perf_gate: key
  local rc=0; ( cd "$co" && _pg check >/dev/null 2>&1 ) || rc=$?
  assert_ok "no perf_gate configured -> no-op (exit 0)" bash -c "[ $rc -eq 0 ]"
}
