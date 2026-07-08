#!/usr/bin/env bash
# lib/config.sh — Orchestrator config loader. Sourced by every tool.
#
# Finds the active company config (orchestrator.yaml), then exposes:
#   ORCH_HOME          dir containing the config (the company repo)
#   ORCH_CONFIG        path to the resolved config file
#   orch_get KEY [def] read a scalar
#   orch_repos         emit one "name:category" per line
#   orch_vetoes        emit one veto per line
#   orch_expand PATH   expand a leading ~ to $HOME
#
# Config resolution order (first hit wins):
#   $ORCH_CONFIG env var → ./orchestrator.yaml → $ORCH_HOME/orchestrator.yaml
#
# The parser is deliberately pure awk/bash — no yq/python dependency — and
# supports exactly the flat schema documented in orchestrator.example.yaml.
set -u

orch_expand() { case "$1" in "~"|"~/"*) printf '%s\n' "${HOME}${1#\~}";; *) printf '%s\n' "$1";; esac; }

_orch_find_config() {
  if [ -n "${ORCH_CONFIG:-}" ] && [ -f "${ORCH_CONFIG}" ]; then printf '%s\n' "$ORCH_CONFIG"; return 0; fi
  if [ -f "./orchestrator.yaml" ]; then printf '%s\n' "$(pwd)/orchestrator.yaml"; return 0; fi
  if [ -n "${ORCH_HOME:-}" ] && [ -f "${ORCH_HOME}/orchestrator.yaml" ]; then printf '%s\n' "${ORCH_HOME}/orchestrator.yaml"; return 0; fi
  return 1
}

ORCH_CONFIG="$(_orch_find_config)" || {
  echo "orchestrator: no orchestrator.yaml found (looked at \$ORCH_CONFIG, ./, \$ORCH_HOME)." >&2
  echo "  Run 'orchestrator init' in your company repo to create one." >&2
  return 1 2>/dev/null || exit 1
}
ORCH_HOME="$(cd "$(dirname "$ORCH_CONFIG")" && pwd)"
export ORCH_CONFIG ORCH_HOME

# orch_get KEY [default] — read a top-level scalar "key: value"
orch_get() {
  local key="$1" def="${2:-}" val
  val="$(awk -v k="$key" '
    /^[A-Za-z0-9_]+:/ {
      ky=$0; sub(/:.*/,"",ky)
      if (ky==k) { v=$0; sub(/^[^:]*:[ \t]*/,"",v); sub(/[ \t]+#.*/,"",v); sub(/^#.*/,"",v); print v; exit }
      # ^ strip an inline comment (whitespace-preceded), then a comment that is
      #   the WHOLE value: an empty scalar + comment leaves "#..." with no
      #   leading space after the key is removed, which the first sub misses (G2).
    }' "$ORCH_CONFIG")"
  [ -n "$val" ] && printf '%s\n' "$val" || printf '%s\n' "$def"
}

# _orch_list SECTION — emit each "- item" under a top-level "section:" block
_orch_list() {
  awk -v s="$1" '
    $0 ~ "^"s":[ \t]*$" { inb=1; next }
    inb && /^[A-Za-z0-9_]+:/ { inb=0 }
    inb && /^[ \t]*-[ \t]*/ { l=$0; sub(/^[ \t]*-[ \t]*/,"",l); sub(/[ \t]+#.*/,"",l); sub(/^#.*/,"",l); sub(/[ \t]+$/,"",l); if (l!="") print l }
    # ^ list items strip inline comments too (G1): the same whitespace-preceded
    #   rule as scalars, plus a comment-only "- # ..." line drops to empty.
  ' "$ORCH_CONFIG"
}

orch_repos()  { _orch_list repos; }   # each line: name:category
orch_vetoes() { _orch_list vetoes; }
