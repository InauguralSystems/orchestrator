#!/usr/bin/env bash
# health --local: scores repos, writes the report + trend, and its exit code.

t_health_green_and_reports() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme-core
  echo MIT > "$root/acme-core/LICENSE"                # a clean repo carries a license
  git -C "$root/acme-core" add .; git -C "$root/acme-core" commit -q -m license
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
  echo MIT > "$root/nocirepo/LICENSE"    # license present, so the only gap is CI
  git -C "$root/nocirepo" add .; git -C "$root/nocirepo" commit -q -m license
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

# _fakegh DIR PRIVATE — write a fake `gh` into DIR that reports green CI and
# repo_meta "OPEN PRIVATE" with the given private flag (true/false), no network.
_fakegh() {
  { echo '#!/usr/bin/env bash'
    echo "case \"\$*\" in *\"run list\"*) echo success;; *\"api\"*) echo \"0 $2\";; *) exit 0;; esac"
  } > "$1/gh"; chmod +x "$1/gh"
}

t_health_governance_counts_present_standards() {
  local root; root="$(mktemp -d)"; mkrepo "$root" good
  echo r > "$root/good/README.md"; echo MIT > "$root/good/LICENSE"; echo s > "$root/good/SECURITY.md"
  git -C "$root/good" add .; git -C "$root/good" commit -q -m standards
  local co; co="$(mkcompany "$root" "good:consumer")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "counts the three present standards" "$out" "3/5"
}

t_health_governance_public_missing_license_warns() {  # G4: public repo, no LICENSE -> WARN
  local root; root="$(mktemp -d)"; mkrepo "$root" pub
  git -C "$root/pub" remote add origin https://github.com/acme/pub
  local co; co="$(mkcompany "$root" "pub:consumer")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" false      # public
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_contains "governance column present (0/5)" "$out" "0/5"
  assert_contains "public repo missing LICENSE warns" "$out" "missing LICENSE"
}

t_health_governance_private_repo_no_license_ok() {  # a private repo needs no license
  local root; root="$(mktemp -d)"; mkrepo "$root" priv
  git -C "$root/priv" remote add origin https://github.com/acme/priv
  local co; co="$(mkcompany "$root" "priv:consumer")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" true       # private
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_missing "private repo not flagged for missing LICENSE" "$out" "missing LICENSE"
}

t_health_governance_exempts_sibling() {  # sibling exempt even when public + no LICENSE
  local root; root="$(mktemp -d)"; mkrepo "$root" sib
  git -C "$root/sib" remote add origin https://github.com/acme/sib
  local co; co="$(mkcompany "$root" "sib:sibling")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" false      # public, yet a sibling
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_missing "sibling is exempt from the missing-LICENSE warn" "$out" "missing LICENSE"
}

t_health_subsidiary_rolls_up_green_child() {  # a subsidiary surfaces its child's OWN verdict
  local root; root="$(mktemp -d)"; mkrepo "$root" childco
  mkdir -p "$root/childco/reports"
  printf -- '- Active repos: OK=5 WARN=0 FAIL=0 -> **GREEN**\n' > "$root/childco/reports/latest.md"
  git -C "$root/childco" add .; git -C "$root/childco" commit -q -m report
  local co; co="$(mkcompany "$root" "childco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "subsidiary shows the rolled-up child verdict" "$out" "**GREEN** — subsidiary roll-up"
  assert_contains "a GREEN child keeps the parent GREEN"          "$out" "→ **GREEN**"
}

t_health_subsidiary_red_child_fails_parent() {  # a RED child must make the parent RED (exit 1)
  local root; root="$(mktemp -d)"; mkrepo "$root" sickco
  mkdir -p "$root/sickco/reports"
  printf -- '- Active repos: OK=1 WARN=0 FAIL=2 -> **RED**\n' > "$root/sickco/reports/latest.md"
  git -C "$root/sickco" add .; git -C "$root/sickco" commit -q -m report
  local co; co="$(mkcompany "$root" "sickco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a RED child rolls up as RED" "$out" "**RED** — subsidiary roll-up"
  assert_contains "a RED child turns the parent RED" "$out" "→ **RED**"
  assert_ok "health exits nonzero when a subsidiary is RED" \
    bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1; [ \$? -eq 1 ]"
}

t_health_subsidiary_missing_report_warns() {  # no child report to roll up -> WARN, never silent-OK
  local root; root="$(mktemp -d)"; mkrepo "$root" noreport
  local co; co="$(mkcompany "$root" "noreport:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a subsidiary with no health report warns" "$out" "no subsidiary health report"
}
