#!/usr/bin/env bash
# The agentic launchers build correct prompts (--dry-run never invokes claude).

t_setup_dry_run() {
  local co; co="$(mkcompany "$(mktemp -d)" "a:product")"
  local out; out="$(runco "$co" setup --dry-run 2>&1)"
  assert_contains "setup names its skill" "$out" "company-setup"
}

t_hire_dry_run() {
  local root; root="$(mktemp -d)"; mkrepo "$root" a
  local co; co="$(mkcompany "$root" "a:product")"
  local out; out="$(runco "$co" hire --dry-run 2>&1)"
  assert_contains "hire names its skill"   "$out" "hiring-manager"
  assert_contains "hire lists the repo"    "$out" "a:product"
}

t_propose_dry_run() {
  local root; root="$(mktemp -d)"; mkrepo "$root" a
  local co; co="$(mkcompany "$root" "a:product")"
  local out; out="$(runco "$co" propose --dry-run 2>&1)"
  assert_contains "propose names its skill" "$out" "portfolio-strategist"
}
