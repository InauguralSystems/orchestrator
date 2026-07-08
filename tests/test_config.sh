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

t_config_strips_inline_comments() {  # G1/G2: inline # comments must not leak into values
  local d; d="$(mktemp -d)"
  cat > "$d/orchestrator.yaml" <<'YAML'
company: TestCo                 # trailing comment on a scalar
github_org:                     # G2: empty value + comment must parse EMPTY
root: /tmp/x
repos:
  - alpha:product              # G1: comment on a list item
  - beta:consumer
vetoes:
  - No feature ships without a test.
YAML
  # G2: an empty scalar followed by a comment resolves to the default, not the comment.
  assert_eq "empty scalar + comment -> default" \
    "$(_load "$d/orchestrator.yaml" 'orch_get github_org NONE')" "NONE"
  # scalar with a real value still strips its trailing comment.
  assert_eq "scalar strips trailing comment" \
    "$(_load "$d/orchestrator.yaml" 'orch_get company')" "TestCo"
  # G1: a list item's category is not polluted by the inline comment.
  assert_eq "list item strips inline comment" \
    "$(_load "$d/orchestrator.yaml" 'orch_repos | head -1')" "alpha:product"
  assert_eq "repo count unaffected" \
    "$(_load "$d/orchestrator.yaml" 'orch_repos | grep -c .')" "2"
}

mkroot_dir() { mktemp -d; }
