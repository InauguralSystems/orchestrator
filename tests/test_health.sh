#!/usr/bin/env bash
# health --local: scores repos, writes the report + trend, and its exit code.

t_health_green_and_reports() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme-core
  local co; co="$(mkcompany "$root" "acme-core:product")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "clean repo scores OK"   "$out" "**OK**"
  assert_contains "company comes up GREEN" "$out" "GREEN"
  assert_ok       "health exits 0 on GREEN" bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1"
  assert_file     "writes reports/latest.md"  "$co/reports/latest.md"
  assert_file     "appends reports/history.csv" "$co/reports/history.csv"
}

t_health_flags_missing_repo() {
  local root; root="$(mktemp -d)"           # empty root — repo not cloned
  local co; co="$(mkcompany "$root" "ghost:consumer")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "uncloned repo warns" "$out" "not cloned"
}

t_health_parked_not_scored() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "gone:parked")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "parked repo not a WARN/FAIL" "$out" "parked"
}

t_health_warns_absent_ci() {  # G9: no CI configured must WARN, not read as green
  local root; root="$(mktemp -d)"; mkrepo "$root" nocirepo
  git -C "$root/nocirepo" remote add origin https://github.com/acme/nocirepo
  local co; co="$(mkcompany "$root" "nocirepo:consumer")"
  # fake gh on PATH: report zero workflow runs ("-") + an open count, no network.
  local fakebin; fakebin="$(mktemp -d)"
  { echo '#!/usr/bin/env bash'
    echo 'case "$*" in *"run list"*) echo "-";; *"api"*) echo 3;; *) exit 0;; esac'
  } > "$fakebin/gh"; chmod +x "$fakebin/gh"
  local out; out="$(cd "$co" && PATH="$fakebin:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_contains "absent CI warns"          "$out" "no CI configured"
  assert_contains "absent-CI repo is WARN"   "$out" "**WARN**"
}
