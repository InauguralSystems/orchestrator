#!/usr/bin/env bash
# lib/config.sh: the pure awk/bash loader parses the documented schema.

_load() { ( export ORCH_CONFIG="$1"; . "$PRODUCT/lib/config.sh" >/dev/null 2>&1; eval "$2" ); }

t_config_scalars() {
  local root; root="$(mkroot_dir)"
  local co; co="$(mkcompany "$root" "a:product" "b:consumer")"
  assert_eq "orch_get company" "$(_load "$co/orchestrator.yaml" 'orch_get company')" "TestCo"
  assert_eq "orch_get root"    "$(_load "$co/orchestrator.yaml" 'orch_get root')" "$root"
  assert_eq "orch_get default when missing" "$(_load "$co/orchestrator.yaml" 'orch_get nope FALLBACK')" "FALLBACK"
}

t_config_lists() {
  local root; root="$(mkroot_dir)"
  local co; co="$(mkcompany "$root" "a:product" "b:consumer" "c:parked")"
  assert_eq "orch_repos count"  "$(_load "$co/orchestrator.yaml" 'orch_repos | grep -c .')" "3"
  assert_contains "orch_repos entry" "$(_load "$co/orchestrator.yaml" 'orch_repos')" "a:product"
  assert_eq "orch_vetoes count" "$(_load "$co/orchestrator.yaml" 'orch_vetoes | grep -c .')" "1"
}

mkroot_dir() { mktemp -d; }
