#!/usr/bin/env bash
# deny_guard.sh — PreToolUse[Bash] guardrail. Denies the catastrophic, mechanical,
# irreversible ops that make an autonomous acceptEdits loop dangerous. It is
# deterministic — the model cannot talk past it — and deliberately minimal
# (defense in depth, not a security boundary): every rule blocks something you
# cannot undo. Rules:
#   1. force-push / delete of a PROTECTED branch (rewriting shared history)
#   2. rm -r of a home/root path (unrecoverable data loss)
# `protected_branches` comes from orchestrator.yaml if reachable, else "main
# master". Override (persistent — touch to disable, rm to restore):
#   touch /tmp/orch_deny_off
#
# NOTE: edit this guard with an editor, NEVER via a Bash command that quotes what
# it blocks — PreToolUse vets the command with the OLD guard (that quirk is why
# content-writing commands, below, are exempt).
set -u
[ -f /tmp/orch_deny_off ] && exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0
# Content-writing commands (heredocs) may legitimately MENTION guarded strings.
case "$cmd" in *"<<"*) exit 0;; esac

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- config (fail-safe: defaults if unreachable) ------------------------
PROTECTED="main master"
if PRODUCT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" && [ -f "$PRODUCT/lib/config.sh" ]; then
  # shellcheck source=/dev/null
  if . "$PRODUCT/lib/config.sh" 2>/dev/null; then
    pb="$(orch_get protected_branches 2>/dev/null || true)"
    [ -n "${pb:-}" ] && PROTECTED="$pb"
  fi
fi

# --- rule 1: force-push / delete of a protected branch ------------------
if printf '%s' "$cmd" | grep -qE '\bgit\b[^;&|]*\bpush\b'; then
  act=""
  printf '%s' "$cmd" | grep -qE '\bpush\b[^;&|]*(--force-with-lease|--force|[[:space:]]-f([[:space:]]|$))' && act="force-push"
  printf '%s' "$cmd" | grep -qE '\bpush\b[^;&|]*(--delete|[[:space:]]:)' && act="delete"
  if [ -n "$act" ]; then
    for b in $PROTECTED; do
      if printf '%s' "$cmd" | grep -qE "([[:space:]/:]|^)${b}([[:space:]]|\$)"; then
        deny "BLOCKED by guardrail (deny_guard): $act touches protected branch '$b'. Rewriting or removing shared history on '$b' is irreversible — use a feature branch and a PR. Override: touch /tmp/orch_deny_off (rm to restore)."
      fi
    done
  fi
fi

# --- rule 2: rm -r of a home/root path ----------------------------------
# A recursive rm (-r / -R in any flag combo) whose target is /, ~, $HOME, or
# /home/<user> — the target must BE the root (a trailing / or subpath is a
# specific dir, not the catastrophe this blocks).
if printf '%s' "$cmd" | grep -qE '\brm\b[^;&|]*[[:space:]]-[A-Za-z]*[rR][A-Za-z]*[^;&|]*[[:space:]](/|~|\$HOME|/home/[^/[:space:]]+)([[:space:]]|$)'; then
  deny "BLOCKED by guardrail (deny_guard): rm -r of a home/root path is unrecoverable. Target a specific subdirectory. Override: touch /tmp/orch_deny_off (rm to restore)."
fi

exit 0
