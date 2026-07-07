#!/usr/bin/env bash
# tests/lib.sh — a self-contained TAP test harness + fixtures. No dependency
# beyond what the product already needs (git/awk/sed/jq/bash), so the suite
# runs anywhere the product does — the standing "zero new dependencies" veto
# applies to the tests too.

TESTS_RUN=0; TESTS_FAIL=0

_pass() { TESTS_RUN=$((TESTS_RUN+1)); printf 'ok %d - %s\n' "$TESTS_RUN" "$1"; }
_fail() {
  TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAIL=$((TESTS_FAIL+1))
  printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
  [ -n "${2:-}" ] && printf '  # %s\n' "$2"
}

assert_eq()       { [ "$2" = "$3" ] && _pass "$1" || _fail "$1" "expected [$3] got [$2]"; }
assert_contains() { case "$2" in *"$3"*) _pass "$1";; *) _fail "$1" "output missing [$3]";; esac; }
assert_missing()  { case "$2" in *"$3"*) _fail "$1" "output unexpectedly had [$3]";; *) _pass "$1";; esac; }
assert_file()     { [ -e "$2" ] && _pass "$1" || _fail "$1" "missing file $2"; }
assert_ok()       { local d="$1"; shift; if "$@" >/dev/null 2>&1; then _pass "$d"; else _fail "$d" "exit $?"; fi; }
assert_fail()     { local d="$1"; shift; if "$@" >/dev/null 2>&1; then _fail "$d" "expected nonzero exit"; else _pass "$d"; fi; }

# --- fixtures ---------------------------------------------------------------
_gitinit() { git -C "$1" init -q; git -C "$1" config user.email t@t.co; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }

mkempty() { local d; d="$(mktemp -d)"; _gitinit "$d"; printf '%s\n' "$d"; }  # git dir, no config

mkrepo() { # $1=root $2=name — a committed git repo under root
  local d="$1/$2"; mkdir -p "$d"; _gitinit "$d"
  echo x > "$d/f"; git -C "$d" add .; git -C "$d" commit -q -m init
}

mkcompany() { # $1=root, rest = "name:category" — echoes the company dir
  local root="$1"; shift
  local co live; co="$(mktemp -d)"; live="$(mktemp -d)"; _gitinit "$co"
  { echo "company: TestCo"; echo "ceo: T"; echo "github_org:"
    echo "root: $root"; echo "live_skills: $live"; echo "skills_dir: skills"
    echo "repos:"; for r in "$@"; do echo "  - $r"; done
    echo "vetoes:"; echo "  - No test left red."
  } > "$co/orchestrator.yaml"
  mkdir -p "$co/skills"
  printf '%s\n' "$co"
}

runco() { local dir="$1"; shift; ( cd "$dir" && "$ORCH_BIN" "$@" ); }  # run CLI in a company
