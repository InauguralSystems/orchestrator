#!/usr/bin/env bash
# sync: live <-> committed mirror, including delete semantics on push.

t_sync_push_and_check() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  local live; live="$(_livedir "$co")"
  mkdir -p "$live/alpha"; echo s > "$live/alpha/SKILL.md"
  runco "$co" sync >/dev/null 2>&1
  assert_file "push mirrors live skill into repo" "$co/skills/alpha/SKILL.md"
  assert_ok   "sync --check clean after push" bash -c "cd '$co' && '$ORCH_BIN' sync --check"
}

t_sync_push_deletes() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  local live; live="$(_livedir "$co")"
  mkdir -p "$live/alpha" "$live/beta"; echo s > "$live/alpha/SKILL.md"; echo s > "$live/beta/SKILL.md"
  runco "$co" sync >/dev/null 2>&1
  rm -rf "$live/beta"                       # fire an employee
  runco "$co" sync >/dev/null 2>&1
  assert_file    "kept employee survives" "$co/skills/alpha/SKILL.md"
  assert_missing "fired employee removed from repo" "$(ls "$co/skills")" "beta"
}

t_sync_install() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  mkdir -p "$co/skills/gamma"; echo s > "$co/skills/gamma/SKILL.md"
  runco "$co" sync --install >/dev/null 2>&1
  assert_file "install mirrors repo skill into live" "$(_livedir "$co")/gamma/SKILL.md"
}

t_sync_install_links_discovery() {  # a non-default live tree gets project-scoped discovery links
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  mkdir -p "$co/skills/gamma"; echo s > "$co/skills/gamma/SKILL.md"
  runco "$co" sync --install >/dev/null 2>&1
  local link="$co/.claude/skills/gamma"
  assert_file "install links skill for Skill-tool discovery" "$link"
  assert_ok   "discovery link resolves to the live SKILL.md" \
    bash -c "[ -L '$link' ] && [ -e '$link/SKILL.md' ]"
  assert_eq   "discovery link points at the LIVE tree, not the mirror" \
    "$(readlink "$link")" "$(_livedir "$co")/gamma"
}

t_sync_link_prunes_and_noops_on_default() {  # prunes a dead link; no bridge for a default-tree company
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  mkdir -p "$co/skills/gamma"; echo s > "$co/skills/gamma/SKILL.md"
  runco "$co" sync --install >/dev/null 2>&1
  rm -rf "$(_livedir "$co")/gamma"                 # remove the skill from LIVE
  runco "$co" sync --link >/dev/null 2>&1
  assert_missing "dangling discovery link pruned" "$(ls "$co/.claude/skills" 2>/dev/null)" "gamma"
  # A company whose live tree IS the auto-discovered ~/.claude/skills needs no bridge.
  local co2; co2="$(mkcompany "$root" "a:product")"
  sed -i "s#^live_skills: .*#live_skills: $HOME/.claude/skills#" "$co2/orchestrator.yaml"
  runco "$co2" sync --link >/dev/null 2>&1
  assert_missing "no discovery dir for a default-tree company" "$(ls -a "$co2")" ".claude"
}

t_sync_refuses_destructive_target() {  # F1: guard against skills_dir: . wiping the repo
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  sed -i 's#^skills_dir: .*#skills_dir: .#' "$co/orchestrator.yaml"   # dangerous typo
  local live; live="$(_livedir "$co")"; mkdir -p "$live/x"; echo s > "$live/x/SKILL.md"
  mkdir -p "$co/skills/keeper"; echo k > "$co/skills/keeper/SKILL.md"   # would be rm -rf'd
  assert_fail "push refuses when skills_dir points at the repo root" \
    bash -c "cd '$co' && '$ORCH_BIN' sync"
  assert_file "committed skills survive the refused push" "$co/skills/keeper/SKILL.md"
}

t_sync_refuses_wrong_live_tree() {  # F2: guard against live_skills pointing at a DIFFERENT company's tree
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  mkdir -p "$co/skills/triage" "$co/skills/security"      # this company's committed roster
  echo s > "$co/skills/triage/SKILL.md"; echo s > "$co/skills/security/SKILL.md"
  local live; live="$(_livedir "$co")"                    # live tree = a DIFFERENT company (disjoint names)
  mkdir -p "$live/eigenscript-perf" "$live/write-eigenscript"
  echo s > "$live/eigenscript-perf/SKILL.md"; echo s > "$live/write-eigenscript/SKILL.md"
  assert_fail "push refuses when live tree shares no skills with the committed roster" \
    bash -c "cd '$co' && '$ORCH_BIN' sync"
  assert_file "committed triage survives the refused push"   "$co/skills/triage/SKILL.md"
  assert_file "committed security survives the refused push" "$co/skills/security/SKILL.md"
  assert_ok   "sync --force overrides the wrong-tree guard" \
    bash -c "cd '$co' && '$ORCH_BIN' sync --force"
}

_livedir() { awk '/^live_skills:/{print $2}' "$1/orchestrator.yaml"; }
