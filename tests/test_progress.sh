#!/usr/bin/env bash
# orchestrator progress — the work loop's first-class external memory. A real
# file the product manages (read with no arg, append a timestamped entry with a
# note), so a later session resumes without re-deriving. Mechanism, not a prompt
# asking the model to "remember to keep a note".

t_progress_empty_reads_without_error() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" progress 2>&1)"
  assert_contains "an empty note reports empty, does not error" "$out" "empty"
  assert_ok       "reading an empty note exits clean" bash -c "cd '$co' && '$ORCH_BIN' progress"
}

t_progress_appends_a_timestamped_entry_readable_back() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  runco "$co" progress "landed the widget" >/dev/null 2>&1
  local out; out="$(runco "$co" progress 2>&1)"
  assert_contains "the appended entry is readable back" "$out" "landed the widget"
  assert_contains "entries carry an ISO-dated stamp"    "$out" "-"
  assert_file     "the default progress file was created" "$co/reports/PROGRESS.md"
}

t_progress_second_entry_appends_not_overwrites() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  runco "$co" progress "first thing"  >/dev/null 2>&1
  runco "$co" progress "second thing" >/dev/null 2>&1
  local out; out="$(runco "$co" progress 2>&1)"
  assert_contains "the first entry survives a second append" "$out" "first thing"
  assert_contains "the second entry is present too"          "$out" "second thing"
}

t_progress_honors_a_custom_path() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  printf 'progress_file: notes/STATE.md\n' >> "$co/orchestrator.yaml"
  runco "$co" progress "custom-path entry" >/dev/null 2>&1
  assert_file     "the configured path is honored" "$co/notes/STATE.md"
  local out; out="$(runco "$co" progress 2>&1)"
  assert_contains "read resolves the same custom path" "$out" "custom-path entry"
}

t_work_prompt_names_the_concrete_progress_file() {  # the mechanism, in the loop
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "the loop is told the real progress-file path"  "$out" "PROGRESS.md"
  assert_contains "the loop appends via the product command"      "$out" "orchestrator progress"
  assert_contains "the loop is told to read it first"             "$out" "READ IT FIRST"
}

t_work_prompt_resumes_from_an_existing_note() {  # external memory survives sessions
  local root; root="$(mktemp -d)"; mkrepo "$root" acme
  local co; co="$(mkcompany "$root" "acme:product")"
  runco "$co" progress "in flight: the frobnicator refactor" >/dev/null 2>&1
  local out; out="$(runco "$co" work --dry-run 2>&1)"
  assert_contains "an existing note's contents are injected for resume" "$out" "frobnicator refactor"
}
