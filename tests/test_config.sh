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

t_config_list_inline_comments() {
  # A list entry may carry a trailing "# comment" just like scalars do; the
  # parser must strip it so the category isn't corrupted (a comment can even
  # contain a colon, which ${entry##*:} would otherwise read as the category).
  local root; root="$(mkroot_dir)"
  local co; co="$(mkcompany "$root" "a:product   # the core: scored as product" "b:parked")"
  assert_eq "orch_repos strips inline comment" \
    "$(_load "$co/orchestrator.yaml" 'orch_repos | head -1')" "a:product"
}

mkroot_dir() { mktemp -d; }
