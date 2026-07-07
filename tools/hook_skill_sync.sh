#!/usr/bin/env bash
# hook_skill_sync.sh — PostToolUse(Write|Edit) hook. When a live skill file
# (~/.claude/skills/...) is created or edited, mirror the skills tree into the
# company repo and commit+push just that directory. Keeps the committed
# employee roster in lockstep with the live one (the standing rule).
#
# Registered in ~/.claude/settings.json by `orchestrator init --hook`, which
# also pins ORCH_CONFIG so the hook knows which company repo to sync into.
# ORCH_SYNC_NO_PUSH=1 skips the push (used by tests).
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" 2>/dev/null || exit 0   # no config -> nothing to do

LIVE="$(orch_expand "$(orch_get live_skills "$HOME/.claude/skills")")"

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
case "$f" in
  "$LIVE"/*) ;;
  *) exit 0 ;;   # not a skill file — nothing to do
esac

bash "$PRODUCT/tools/sync_skills.sh" --push >/dev/null 2>&1 || exit 0

cd "$ORCH_HOME" || exit 0
SKILLS_DIR="$(orch_get skills_dir skills)"
git add "$SKILLS_DIR" >/dev/null 2>&1
if ! git diff --cached --quiet -- "$SKILLS_DIR"; then
  slug=${f#"$LIVE"/}; slug=${slug%%/*}
  git commit -q -m "skills: sync ${slug} (live -> repo, auto)" -- "$SKILLS_DIR" 2>/dev/null
  [ "${ORCH_SYNC_NO_PUSH:-0}" = "1" ] || git push -q 2>/dev/null
  echo "{\"systemMessage\": \"orchestrator: ${SKILLS_DIR}/${slug} synced and committed\"}"
fi
exit 0
