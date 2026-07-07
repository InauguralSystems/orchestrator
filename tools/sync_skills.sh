#!/usr/bin/env bash
# sync_skills.sh — keep the committed copy (this repo's skills/) and the live
# tree (~/.claude/skills/) in sync. The LIVE tree is the source of truth; the
# committed copy exists so a fresh machine can bootstrap the company.
#
#   tools/sync_skills.sh            # push: live -> repo (default; then review + commit)
#   tools/sync_skills.sh --install  # install: repo -> live (new machine)
#   tools/sync_skills.sh --check    # report drift, exit 1 if any
set -euo pipefail

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1

LIVE="$(orch_expand "$(orch_get live_skills "$HOME/.claude/skills")")"
REPO="$ORCH_HOME/$(orch_get skills_dir skills)"
MODE="${1:---push}"

drift() { diff -rq "$LIVE" "$REPO" 2>&1 | grep -v '^Common' || true; }

# safe_delete_target DST — a destructive (--delete) mirror is only allowed into a
# skills dir strictly *inside* the company repo. This blocks a config typo
# (skills_dir: . / .. / ~) from turning `sync --push` into an rm -rf of $HOME,
# /, or the repo root. Returns 0 if DST is safe to --delete into.
safe_delete_target() {
  local dst home
  mkdir -p "$1" 2>/dev/null || return 1
  dst="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  home="$(cd "$ORCH_HOME" 2>/dev/null && pwd -P)" || return 1
  case "$dst" in ""|"/"|"$HOME") return 1;; esac
  [ "$dst" = "$home" ] && return 1          # never the repo root itself
  case "$dst/" in "$home"/*) return 0;; *) return 1;; esac  # must be under the repo
}

# mirror SRC DST [--delete] — copy SRC/* into DST. With --delete, DST becomes an
# exact mirror of SRC (entries not in SRC are removed). Prefers rsync; falls
# back to cp so rsync is optional, not required.
mirror() {
  local src="$1" dst="$2" del="${3:-}"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    [ "$del" = "--delete" ] && rsync -a --delete "$src/" "$dst/" || rsync -a "$src/" "$dst/"
  else
    if [ "$del" = "--delete" ]; then
      # drop dst entries that no longer exist in src (top-level skill dirs)
      for d in "$dst"/*/; do
        [ -e "$d" ] || continue; local name; name="$(basename "$d")"
        [ -e "$src/$name" ] || rm -rf "$d"
      done
    fi
    cp -a "$src"/. "$dst"/ 2>/dev/null || (cd "$src" && cp -R . "$dst"/)
  fi
}

case "$MODE" in
  --push)
    if ! safe_delete_target "$REPO"; then
      echo "sync: refusing destructive mirror into '$REPO' — skills_dir must be a" >&2
      echo "      subdirectory inside the company repo ($ORCH_HOME), not . / .. / ~ / /." >&2
      exit 1
    fi
    mirror "$LIVE" "$REPO" --delete
    echo "Pushed live -> repo: $(ls "$REPO" 2>/dev/null | wc -l | tr -d ' ') skills. Review with 'git -C $ORCH_HOME diff', then commit."
    ;;
  --install)
    [ -d "$REPO" ] || { echo "No committed skills at $REPO" >&2; exit 1; }
    mirror "$REPO" "$LIVE"   # no --delete: never destroy machine-local skills
    echo "Installed repo -> live: $(ls "$REPO" 2>/dev/null | wc -l | tr -d ' ') skills into $LIVE (machine-local extras preserved)."
    ;;
  --check)
    d="$(drift)"
    if [ -z "$d" ]; then echo "skills in sync"; exit 0; fi
    echo "$d"; echo "DRIFT: $(echo "$d" | wc -l | tr -d ' ') differing entries. 'orchestrator sync' to push live -> repo."
    exit 1
    ;;
  *) echo "usage: $0 [--push|--install|--check]" >&2; exit 2;;
esac
