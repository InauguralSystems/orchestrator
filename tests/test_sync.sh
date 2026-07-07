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

_livedir() { awk '/^live_skills:/{print $2}' "$1/orchestrator.yaml"; }
