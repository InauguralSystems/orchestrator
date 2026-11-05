#!/usr/bin/env bash
# tests/test_publish.sh — tools/publish_reports.sh against a local bare remote.
# Every case reads the REMOTE afterwards: the script's own "published" line is
# not evidence that anything arrived.

PUB="$PRODUCT/tools/publish_reports.sh"

# A clone on a feature branch with a dirty tree, and its bare remote.
# Echoes "<work> <remote>".
_pub_fixture() {
  local base work remote; base="$(mktemp -d)"; remote="$base/remote.git"; work="$base/work"
  git init -q --bare -b main "$remote"
  git clone -q "$remote" "$work" 2>/dev/null; _gitinit "$work"
  mkdir -p "$work/reports"
  echo tracked > "$work/tracked.txt"; echo "reports/ignored.csv" > "$work/.gitignore"
  git -C "$work" add tracked.txt .gitignore; git -C "$work" commit -q -m init
  git -C "$work" push -q origin HEAD:main; git -C "$work" remote set-head origin main >/dev/null
  git -C "$work" checkout -q -b some-pr-branch
  echo dirty >> "$work/tracked.txt"                      # unrelated uncommitted work
  echo "board v1" > "$work/reports/latest.md"
  echo "d,1"      > "$work/reports/ignored.csv"
  printf '%s %s\n' "$work" "$remote"
}
_rshow()  { git -C "$1" show "reports:$2" 2>/dev/null; }                 # $1=remote $2=path
_rcount() { git -C "$1" rev-list --count reports 2>/dev/null || echo 0; }
_state()  { printf '%s|%s|%s' "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" branch --show-current)" "$(git -C "$1" status --porcelain | sort | tr '\n' ';')"; }

t_publish_lands_and_leaves_checkout_alone() {
  local work remote before out; read -r work remote < <(_pub_fixture)
  before="$(_state "$work")"
  out="$(bash "$PUB" -C "$work" -m "sweep 1" reports reports/latest.md reports/ignored.csv 2>&1)"
  assert_contains "first publish reports success" "$out" "published"
  assert_eq "remote reports branch holds the board"          "$(_rshow "$remote" reports/latest.md)" "board v1"
  assert_eq "a gitignored report file is published too"      "$(_rshow "$remote" reports/ignored.csv)" "d,1"
  assert_eq "branch tree is exactly the named files"         "$(git -C "$remote" ls-tree -r --name-only reports | tr '\n' ' ')" "reports/ignored.csv reports/latest.md "
  assert_eq "HEAD, branch and dirty tree are untouched"      "$(_state "$work")" "$before"
  assert_eq "remote main did not move" "$(git -C "$remote" rev-list --count main)" "1"
}

t_publish_chains_and_skips_unchanged() {
  local work remote out; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  echo "board v2" > "$work/reports/latest.md"
  bash "$PUB" -C "$work" -m "sweep 2" reports reports/latest.md >/dev/null 2>&1
  assert_eq "second run adds one commit on the first" "$(_rcount "$remote")" "2"
  assert_eq "second run's content is on the remote"   "$(_rshow "$remote" reports/latest.md)" "board v2"
  assert_eq "commit message is the one given"         "$(git -C "$remote" log -1 --format=%s reports)" "sweep 2"
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; local rc=$?
  assert_eq "an unchanged run exits 0"            "$rc" "0"
  assert_contains "and says unchanged"            "$out" "unchanged"
  assert_eq "and adds no commit"                  "$(_rcount "$remote")" "2"
}

t_publish_refuses_default_branch() {
  local work remote rc; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" main reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "publishing to main is refused (exit 3)" "$rc" "3"
  assert_eq "remote main did not move" "$(git -C "$remote" rev-list --count main)" "1"
  bash "$PUB" -C "$work" master reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "publishing to master is refused (exit 3)" "$rc" "3"
  # A default branch with another name is refused through origin/HEAD.
  git -C "$work" push -q origin main:trunk; git -C "$remote" symbolic-ref HEAD refs/heads/trunk
  git -C "$work" fetch -q origin; git -C "$work" remote set-head origin trunk >/dev/null
  bash "$PUB" -C "$work" trunk reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "the remote's own default branch is refused (exit 3)" "$rc" "3"
  assert_eq "remote trunk did not move" "$(git -C "$remote" rev-list --count trunk)" "1"
}

t_publish_refuses_checked_out_branch() {
  local work remote rc; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  # Someone checks the reports branch out (the untracked copies would block it).
  git -C "$work" checkout -q -- tracked.txt; rm -rf "$work/reports"
  git -C "$work" checkout -q reports
  assert_eq "fixture: the reports branch is checked out" "$(git -C "$work" branch --show-current)" "reports"
  echo "board v9" > "$work/reports/latest.md"
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "a checked-out target branch is refused (exit 3)" "$rc" "3"
  assert_eq "and nothing was pushed" "$(_rcount "$remote")" "1"
}

t_publish_zero_files_is_a_failure() {
  local work remote rc out; read -r work remote < <(_pub_fixture)
  out="$(bash "$PUB" -C "$work" reports reports/nope.md reports/also-nope.md 2>&1)"; rc=$?
  assert_eq "no existing file exits 2" "$rc" "2"
  assert_contains "and says nothing was published" "$out" "nothing to publish"
  assert_eq "no reports branch was created" "$(git -C "$remote" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
}

t_publish_queues_when_push_fails_then_drains() {
  local work remote rc out; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  mv "$remote" "$remote.gone"                              # the remote is unreachable
  echo "board v2" > "$work/reports/latest.md"
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "a failed push exits 5" "$rc" "5"
  assert_contains "and says so loudly" "$out" "PUSH FAILED"
  echo "board v3" > "$work/reports/latest.md"
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  mv "$remote.gone" "$remote"                              # back
  echo "board v4" > "$work/reports/latest.md"
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "the next run with the remote back exits 0" "$rc" "0"
  assert_eq "every queued commit arrived, in order" "$(_rcount "$remote")" "4"
  assert_eq "newest content is on the remote" "$(_rshow "$remote" reports/latest.md)" "board v4"
}

t_publish_builds_on_a_remote_that_moved_ahead() {
  local work remote other; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  other="$(mktemp -d)/other"; git clone -q "$remote" "$other" 2>/dev/null; _gitinit "$other"
  mkdir -p "$other/reports"; echo "from the other box" > "$other/reports/latest.md"
  bash "$PUB" -C "$other" reports reports/latest.md >/dev/null 2>&1
  echo "board v3" > "$work/reports/latest.md"
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  assert_eq "the run chains on the other box's commit" "$(_rcount "$remote")" "3"
  assert_eq "and its content wins" "$(_rshow "$remote" reports/latest.md)" "board v3"
}

t_publish_never_forces_over_a_diverged_remote() {
  local work remote other rc tip; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  # Queue a local commit the remote never sees...
  mv "$remote" "$remote.gone"; echo "local only" > "$work/reports/latest.md"
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1
  mv "$remote.gone" "$remote"
  # ...while another clone publishes a different commit on the same parent.
  other="$(mktemp -d)/other"; git clone -q "$remote" "$other" 2>/dev/null; _gitinit "$other"
  mkdir -p "$other/reports"; echo "remote only" > "$other/reports/latest.md"
  bash "$PUB" -C "$other" reports reports/latest.md >/dev/null 2>&1
  tip="$(git -C "$remote" rev-parse reports)"
  bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "a diverged remote exits 4" "$rc" "4"
  assert_eq "and the remote tip is not overwritten" "$(git -C "$remote" rev-parse reports)" "$tip"
}

# --- the sweep itself ---------------------------------------------------------
# A company with a bare remote, on a PR branch. Echoes "<co> <remote>".
_sweep_fixture() {
  local root co remote; root="$(mktemp -d)"; mkrepo "$root" app
  co="$(mkcompany "$root" app:product)"; remote="$(mktemp -d)/remote.git"
  git init -q --bare -b main "$remote"
  git -C "$co" add -A; git -C "$co" commit -q -m init
  git -C "$co" remote add origin "$remote"; git -C "$co" push -q origin HEAD:main
  git -C "$co" checkout -q -b some-pr-branch
  printf '%s %s\n' "$co" "$remote"
}

t_sweep_with_reports_branch_publishes_there() {
  local co remote out head; read -r co remote < <(_sweep_fixture)
  echo "reports_branch: reports" >> "$co/orchestrator.yaml"
  head="$(git -C "$co" rev-parse HEAD)"
  out="$(runco "$co" sweep 2>&1)"
  assert_contains "sweep says it published" "$out" "published"
  assert_ok "the board is on the remote reports branch"   git -C "$remote" cat-file -e reports:reports/latest.md
  assert_ok "the trend is on the remote reports branch"   git -C "$remote" cat-file -e reports:reports/history.csv
  assert_ok "the dashboard is on the remote reports branch" git -C "$remote" cat-file -e reports:reports/dashboard.html
  assert_eq "no commit was made on the checkout's branch" "$(git -C "$co" rev-parse HEAD)" "$head"
  assert_eq "nothing was left staged" "$(git -C "$co" diff --cached --name-only | wc -l | tr -d ' ')" "0"
  assert_eq "the PR branch was not pushed" "$(git -C "$remote" for-each-ref refs/heads/some-pr-branch | wc -l | tr -d ' ')" "0"
  assert_eq "remote main did not move" "$(git -C "$remote" rev-list --count main)" "1"
}

t_sweep_reports_publish_adds_files() {
  local co remote; read -r co remote < <(_sweep_fixture)
  { echo "reports_branch: reports"; echo "reports_publish:"; echo "  - reports/extra.csv"; } >> "$co/orchestrator.yaml"
  mkdir -p "$co/reports"; echo "a,b" > "$co/reports/extra.csv"
  runco "$co" sweep >/dev/null 2>&1
  assert_eq "a reports_publish file is published" "$(git -C "$remote" show reports:reports/extra.csv 2>/dev/null)" "a,b"
}

t_sweep_shouts_when_publish_fails() {
  local co remote out; read -r co remote < <(_sweep_fixture)
  echo "reports_branch: main" >> "$co/orchestrator.yaml"      # refused by publish_reports.sh
  out="$(runco "$co" sweep 2>&1)"
  assert_contains "a refused publish is loud in the sweep log" "$out" "ATTENTION: reports were NOT published"
  assert_eq "and remote main did not move" "$(git -C "$remote" rev-list --count main)" "1"
}

t_sweep_without_reports_branch_keeps_the_old_path() {
  local co remote; read -r co remote < <(_sweep_fixture)
  git -C "$co" push -q -u origin some-pr-branch
  runco "$co" sweep >/dev/null 2>&1
  assert_eq "the default still commits on the current branch" "$(git -C "$co" log -1 --format=%s | cut -c1-19)" "sweep: daily report"
  assert_eq "and creates no reports branch" "$(git -C "$remote" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
}
