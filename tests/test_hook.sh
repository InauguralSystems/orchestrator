#!/usr/bin/env bash
# hook_skill_sync.sh: auto-commits on a live skill edit, no-ops otherwise.

_hook() { echo "$3" | ORCH_CONFIG="$1/orchestrator.yaml" ORCH_SYNC_NO_PUSH=1 bash "$PRODUCT/tools/hook_skill_sync.sh"; }
_livedir() { awk '/^live_skills:/{print $2}' "$1/orchestrator.yaml"; }

t_hook_commits_on_skill_edit() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  local live; live="$(_livedir "$co")"
  mkdir -p "$live/newhire"; echo s > "$live/newhire/SKILL.md"
  _hook "$co" "" "{\"tool_input\":{\"file_path\":\"$live/newhire/SKILL.md\"}}" >/dev/null 2>&1
  assert_file "hook mirrors the new skill" "$co/skills/newhire/SKILL.md"
  local msg; msg="$(git -C "$co" log -1 --format=%s 2>/dev/null)"
  assert_contains "hook made an auto-commit" "$msg" "sync newhire"
}

t_hook_noop_on_nonskill() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "a:product")"
  local before; before="$(git -C "$co" rev-list --count HEAD 2>/dev/null || echo 0)"
  _hook "$co" "" '{"tool_input":{"file_path":"/etc/hosts"}}' >/dev/null 2>&1
  local after; after="$(git -C "$co" rev-list --count HEAD 2>/dev/null || echo 0)"
  assert_eq "non-skill edit makes no commit" "$after" "$before"
}
