#!/usr/bin/env bash
# orch_ghslug (lib/config.sh) + the standup PR section: the GitHub slug is
# derived from the repo's remote, so a directory name that differs from the
# GitHub repo name resolves instead of silently 404-ing; a subsidiary is
# surfaced explicitly rather than contributing a silent empty list.

t_ghslug_ssh_remote_dir_ne_repo() {
  # The real regression: dir "dot-github" but GitHub repo ".github". A naive
  # "$org/dir" would query InauguralSystems/dot-github and 404 into "no PRs".
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "dot-github"
  git -C "$root/dot-github" remote add origin "git@github.com:InauguralSystems/.github.git"
  local co; co="$(mkcompany "$root" "dot-github:infra")"
  assert_eq "ghslug derives repo name from ssh remote (dir != repo)" \
    "$(_load "$co/orchestrator.yaml" 'orch_ghslug dot-github')" "InauguralSystems/.github"
}

t_ghslug_https_remote() {
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "proj"
  git -C "$root/proj" remote add origin "https://github.com/Acme/Proj.git"
  local co; co="$(mkcompany "$root" "proj:product")"
  assert_eq "ghslug parses an https remote and strips .git" \
    "$(_load "$co/orchestrator.yaml" 'orch_ghslug proj')" "Acme/Proj"
}

t_ghslug_fallback_to_org() {
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "noremote"   # committed repo, no origin remote
  local d; d="$(mktemp -d)"
  cat > "$d/orchestrator.yaml" <<YAML
company: TestCo
github_org: MyOrg
root: $root
repos:
  - noremote:product
vetoes:
  - No test left red.
YAML
  assert_eq "ghslug falls back to \$github_org/name with no remote" \
    "$(_load "$d/orchestrator.yaml" 'orch_ghslug noremote')" "MyOrg/noremote"
}

t_standup_surfaces_subsidiary() {
  command -v gh >/dev/null 2>&1 || { _pass "standup names subsidiary (skipped: no gh)"; return; }
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "hq"
  local d; d="$(mktemp -d)"
  cat > "$d/orchestrator.yaml" <<YAML
company: TestCo
github_org: TestOrg
root: $root
repos:
  - hq:subsidiary
vetoes:
  - No test left red.
YAML
  local out
  out="$(ORCH_CONFIG="$d/orchestrator.yaml" STANDUP_LOCAL=0 bash "$PRODUCT/tools/standup.sh" 2>/dev/null)"
  assert_contains "standup names the subsidiary in the PR section" "$out" "(subsidiary)"
}
