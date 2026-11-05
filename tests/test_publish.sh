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

# --- what it refuses ----------------------------------------------------------
t_publish_default_guard_does_not_need_a_cached_head() {
  local work remote rc; read -r work remote < <(_pub_fixture)
  git -C "$work" push -q origin main:trunk; git -C "$remote" symbolic-ref HEAD refs/heads/trunk
  git -C "$work" remote set-head origin -d >/dev/null          # no cached origin/HEAD at all
  bash "$PUB" -C "$work" trunk reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "the default is learned from the remote itself (exit 3)" "$rc" "3"
  assert_eq "remote trunk did not move" "$(git -C "$remote" rev-list --count trunk)" "1"
}

t_publish_fails_closed_when_default_is_unknowable() {
  local work remote rc out; read -r work remote < <(_pub_fixture)
  git -C "$work" remote set-head origin -d >/dev/null
  mv "$remote" "$remote.gone"                                   # cannot ask, nothing cached
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "an unknowable default branch is a refusal (exit 3)" "$rc" "3"
  assert_contains "and says why" "$out" "cannot learn"
  assert_eq "no local reports branch was made" "$(git -C "$work" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
}

t_publish_refuses_extra_protected_names() {
  local work remote rc; read -r work remote < <(_pub_fixture)
  PUBLISH_REFUSE="release staging" bash "$PUB" -C "$work" staging reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "a name in PUBLISH_REFUSE is refused (exit 3)" "$rc" "3"
  assert_eq "and no such branch was created" "$(git -C "$remote" for-each-ref refs/heads/staging | wc -l | tr -d ' ')" "0"
}

t_publish_refuses_a_branch_it_did_not_make() {
  local work remote rc tip out; read -r work remote < <(_pub_fixture)
  git -C "$work" push -q origin some-pr-branch:feature          # a code branch on the remote
  tip="$(git -C "$remote" rev-parse feature)"
  out="$(bash "$PUB" -C "$work" feature reports/latest.md 2>&1)"; rc=$?
  assert_eq "an existing code branch is refused (exit 3)" "$rc" "3"
  assert_contains "and says it is not a reports branch" "$out" "not a reports branch"
  assert_eq "the code branch is untouched" "$(git -C "$remote" rev-parse feature)" "$tip"
  assert_eq "and still has its code" "$(git -C "$remote" show feature:tracked.txt)" "tracked"
}

t_publish_refuses_symlinks_and_paths_outside_reports() {
  local work remote rc secret; read -r work remote < <(_pub_fixture)
  secret="$(mktemp)"; echo "PRIVATE KEY" > "$secret"
  ln -s "$secret" "$work/reports/link.md"
  bash "$PUB" -C "$work" reports reports/latest.md reports/link.md >/dev/null 2>&1; rc=$?
  assert_eq "a symlinked report file is refused (exit 2)" "$rc" "2"
  mkdir -p "$work/elsewhere"; echo "PRIVATE KEY" > "$work/elsewhere/s.md"
  ln -s ../elsewhere "$work/reports/sub"
  bash "$PUB" -C "$work" reports reports/latest.md reports/sub/s.md >/dev/null 2>&1; rc=$?
  assert_eq "a file reached through a symlinked directory is refused (exit 2)" "$rc" "2"
  ln -s /nonexistent "$work/reports/dangling.md"
  bash "$PUB" -C "$work" reports reports/latest.md reports/dangling.md >/dev/null 2>&1; rc=$?
  assert_eq "a dangling symlink is refused, not skipped (exit 2)" "$rc" "2"
  bash "$PUB" -C "$work" reports reports/latest.md tracked.txt >/dev/null 2>&1; rc=$?
  assert_eq "a file outside reports/ is refused (exit 2)" "$rc" "2"
  local why; why="$(bash "$PUB" -C "$work" reports reports/latest.md reports/../tracked.txt 2>&1)"; rc=$?
  assert_eq "a .. path is refused (exit 2)" "$rc" "2"
  assert_contains "by this script's own path check, before git sees it" "$why" "not a normal path"
  bash "$PUB" -C "$work" reports reports/latest.md "$secret" >/dev/null 2>&1; rc=$?
  assert_eq "an absolute path is refused (exit 2)" "$rc" "2"
  assert_eq "none of those runs published anything" "$(git -C "$remote" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
}

t_publish_marks_its_commits() {
  local work remote; read -r work remote < <(_pub_fixture)
  bash "$PUB" -C "$work" -m "sweep 1" reports reports/latest.md >/dev/null 2>&1
  assert_eq "the commit carries the reports-branch marker" "$(git -C "$remote" log -1 --format=%B reports | grep -cxF 'Published-By: publish_reports.sh')" "1"
}

t_sweep_refuses_a_protected_branch_from_config() {
  local co remote out; read -r co remote < <(_sweep_fixture)
  { echo "protected_branches: main release"; echo "reports_branch: release"; } >> "$co/orchestrator.yaml"
  out="$(runco "$co" sweep 2>&1)"
  assert_contains "a protected_branches name is refused by the sweep" "$out" "ATTENTION: reports were NOT published"
  assert_eq "and no such branch was created" "$(git -C "$remote" for-each-ref refs/heads/release | wc -l | tr -d ' ')" "0"
}

t_publish_refuses_a_name_used_as_a_prefix() {
  local work remote rc out; read -r work remote < <(_pub_fixture)
  git -C "$work" push -q origin some-pr-branch:reports/regen-2026-q3    # on the remote only
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "a name the remote uses as a prefix is refused (exit 3)" "$rc" "3"
  assert_contains "and names the branch in the way" "$out" "reports/regen-2026-q3"
  git -C "$work" push -q origin :reports/regen-2026-q3
  git -C "$work" branch -q reports/local-only                           # in this clone only
  out="$(bash "$PUB" -C "$work" reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "so is one this clone uses as a prefix (exit 3)" "$rc" "3"
  assert_contains "and names it" "$out" "reports/local-only"
  assert_eq "nothing was published either time" "$(git -C "$remote" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
}

# --- files that keep history (-k, --restore) -----------------------------------
# After the report files leave the default branch, the reports branch holds the
# only durable copy of the trend. These cases are the ones a passing suite
# missed the first time: a checkout that has no history of its own.
_fresh_clone() { local d; d="$(mktemp -d)/fresh"; git clone -q "$1" "$d" 2>/dev/null; _gitinit "$d"; printf '%s\n' "$d"; }
_hist() { printf '%s\n' "$@"; }                                   # lines -> a history file
# A work clone that has published "h,r1,r2" as reports/history.csv. Echoes "<work> <remote>".
_hist_fixture() {
  local work remote; read -r work remote < <(_pub_fixture)
  _hist h r1 r2 > "$work/reports/history.csv"
  bash "$PUB" -C "$work" -k reports/history.csv reports reports/latest.md >/dev/null 2>&1
  printf '%s %s\n' "$work" "$remote"
}

t_restore_writes_a_missing_history_file() {
  local work remote fresh out rc; read -r work remote < <(_hist_fixture)
  assert_eq "fixture: the trend is on the remote" "$(_rshow "$remote" reports/history.csv | tr '\n' ' ')" "h r1 r2 "
  fresh="$(_fresh_clone "$remote")"
  out="$(bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports 2>&1)"; rc=$?
  assert_eq "restore exits 0" "$rc" "0"
  assert_contains "and says what it did" "$out" "restored reports/history.csv"
  assert_eq "a fresh clone gets the published trend" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 "
  assert_eq "restore commits nothing" "$(_rcount "$remote")" "1"
  assert_eq "and leaves the checkout's branch and index alone" "$(git -C "$fresh" status --porcelain | tr -d '\n')" "?? reports/"
  : > "$fresh/reports/history.csv"
  bash "$PUB" --restore -C "$fresh" reports reports/history.csv >/dev/null 2>&1
  assert_eq "an empty local file is restored too (positional form)" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 "
}

t_restore_puts_back_what_the_local_copy_lacks() {
  local work remote fresh out; read -r work remote < <(_hist_fixture)
  fresh="$(_fresh_clone "$remote")"; mkdir -p "$fresh/reports"
  _try() { _hist "$@" > "$fresh/reports/history.csv"; bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports 2>&1; }
  _try h today >/dev/null
  assert_eq "a file the generator just started keeps the trend and today's row" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 today "
  _try h r1 >/dev/null
  assert_eq "a local copy that is behind catches up, nothing doubled" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 "
  _try h r1 x >/dev/null
  assert_eq "a local-only row survives after the published ones" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 x "
  _try r2 today >/dev/null
  assert_eq "a local copy missing its start is completed, overlap not doubled" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 today "
  out="$(_try h r1 r2 today)"
  assert_eq "an up-to-date local copy is not rewritten" "$(tr '\n' ' ' < "$fresh/reports/history.csv")" "h r1 r2 today "
  assert_eq "and restore is silent about it" "$out" ""
}

t_restore_rewrites_in_place_for_an_open_appender() {
  # The sweep log is appended to by cron's `>>` while the sweep restores it.
  local work remote fresh; read -r work remote < <(_hist_fixture)
  fresh="$(_fresh_clone "$remote")"; mkdir -p "$fresh/reports"
  ( exec 9>>"$fresh/reports/history.csv"
    echo "run start" >&9
    bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports >&9 2>&1
    echo "run end" >&9 )
  assert_eq "published lines first, then the run's own lines, appends still land" \
    "$(grep -v '^publish_reports:' "$fresh/reports/history.csv" | tr '\n' ' ')" "h r1 r2 run start run end "
}

t_restore_with_nothing_published_is_a_pass() {
  local work remote rc out; read -r work remote < <(_pub_fixture)
  out="$(bash "$PUB" --restore -C "$work" -k reports/history.csv reports 2>&1)"; rc=$?
  assert_eq "no reports branch yet: exit 0" "$rc" "0"
  assert_contains "and says there is nothing to restore" "$out" "nothing to restore"
  assert_eq "and creates no file" "$([ -e "$work/reports/history.csv" ] && echo yes || echo no)" "no"
}

t_restore_says_so_when_the_remote_is_unreachable() {
  local work remote fresh rc out; read -r work remote < <(_hist_fixture)
  fresh="$(_fresh_clone "$remote")"; git -C "$fresh" remote set-head origin main >/dev/null
  git -C "$fresh" update-ref -d refs/remotes/origin/reports       # this clone never saw the branch
  mv "$remote" "$remote.gone"
  out="$(bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports 2>&1)"; rc=$?
  assert_eq "unreachable and no copy: exit 5" "$rc" "5"
  assert_contains "and says restore failed" "$out" "RESTORE FAILED"
  # The clone that published still has its own copy of the branch.
  rm -f "$work/reports/history.csv"
  out="$(bash "$PUB" --restore -C "$work" -k reports/history.csv reports 2>&1)"; rc=$?
  assert_eq "unreachable with a cached copy: still exit 5" "$rc" "5"
  assert_contains "and says the copy may be old" "$out" "RESTORE INCOMPLETE"
  assert_eq "but the last known trend is put back" "$(tr '\n' ' ' < "$work/reports/history.csv")" "h r1 r2 "
  mv "$remote.gone" "$remote"
}

t_restore_refuses_symlinks_and_foreign_branches() {
  local work remote fresh rc victim; read -r work remote < <(_hist_fixture)
  fresh="$(_fresh_clone "$remote")"; mkdir -p "$fresh/reports"
  victim="$(mktemp)"; echo "do not overwrite" > "$victim"
  ln -s "$victim" "$fresh/reports/history.csv"
  bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports >/dev/null 2>&1; rc=$?
  assert_eq "restore through a symlink is refused (exit 2)" "$rc" "2"
  assert_eq "and the link's target is untouched" "$(cat "$victim")" "do not overwrite"
  rm -f "$fresh/reports/history.csv"
  # A code branch that happens to carry reports/history.csv is not a source.
  git -C "$work" checkout -q -- tracked.txt
  git -C "$work" add -f reports/history.csv; git -C "$work" commit -q -m "code branch with a report file"
  git -C "$work" push -q origin some-pr-branch:feature
  bash "$PUB" --restore -C "$fresh" -k reports/history.csv feature >/dev/null 2>&1; rc=$?
  assert_eq "restoring from a branch this script did not make is refused (exit 3)" "$rc" "3"
  assert_eq "and nothing was written" "$([ -e "$fresh/reports/history.csv" ] && echo yes || echo no)" "no"
}

t_publish_refuses_to_drop_published_history() {
  local work remote fresh rc out tip; read -r work remote < <(_hist_fixture)
  tip="$(git -C "$remote" rev-parse reports)"
  fresh="$(_fresh_clone "$remote")"; mkdir -p "$fresh/reports"; echo "board from fresh" > "$fresh/reports/latest.md"
  _hist h today > "$fresh/reports/history.csv"                  # what a generator writes with no history
  out="$(bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "a history file that lost published lines is refused (exit 6)" "$rc" "6"
  assert_contains "and names the file" "$out" "reports/history.csv keeps history"
  assert_eq "the remote tip did not move" "$(git -C "$remote" rev-parse reports)" "$tip"
  rm -f "$fresh/reports/history.csv"
  bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "so is dropping the history file altogether (exit 6)" "$rc" "6"
  assert_eq "the remote tip still did not move" "$(git -C "$remote" rev-parse reports)" "$tip"
  _hist h r1 r2 today > "$fresh/reports/history.csv"
  bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "an append is published (exit 0)" "$rc" "0"
  assert_eq "and is on the remote" "$(_rshow "$remote" reports/history.csv | tr '\n' ' ')" "h r1 r2 today "
  _hist h trimmed > "$fresh/reports/history.csv"
  PUBLISH_ALLOW_REWRITE=1 bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "a deliberate trim needs the override, and then publishes" "$rc" "0"
  assert_eq "the trimmed file is on the remote" "$(_rshow "$remote" reports/history.csv | tr '\n' ' ')" "h trimmed "
}

t_publish_is_byte_exact_whatever_git_is_configured_to_do() {
  local work remote; read -r work remote < <(_pub_fixture)
  git -C "$work" config filter.shout.clean "tr a-z A-Z"
  git -C "$work" config core.autocrlf true
  mkdir -p "$work/.git/info"; echo "reports/*.md filter=shout" > "$work/.git/info/attributes"
  printf 'board line one\r\nline two\r\n' > "$work/reports/latest.md"
  printf 'd,1\r\n' > "$work/reports/crlf.csv"
  bash "$PUB" -C "$work" reports reports/latest.md reports/crlf.csv >/dev/null 2>&1
  assert_ok "a clean filter does not change the published board" \
    bash -c 'git -C "$1" cat-file blob reports:reports/latest.md | cmp -s - "$2/reports/latest.md"' _ "$remote" "$work"
  assert_ok "autocrlf does not change a published file" \
    bash -c 'git -C "$1" cat-file blob reports:reports/crlf.csv | cmp -s - "$2/reports/crlf.csv"' _ "$remote" "$work"
}

t_publish_does_not_depend_on_realpath() {
  local work remote shim rc; read -r work remote < <(_pub_fixture)
  shim="$(mktemp -d)"; printf '#!/bin/sh\nexit 127\n' > "$shim/realpath"; chmod +x "$shim/realpath"
  PATH="$shim:$PATH" bash "$PUB" -C "$work" reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "an ordinary report publishes where realpath does not work" "$rc" "0"
  assert_eq "and it is on the remote" "$(_rshow "$remote" reports/latest.md)" "board v1"
}

t_publish_waits_for_the_remote_rather_than_start_a_second_history() {
  local work remote fresh rc out; read -r work remote < <(_hist_fixture)
  fresh="$(_fresh_clone "$remote")"; git -C "$fresh" remote set-head origin main >/dev/null
  git -C "$fresh" update-ref -d refs/remotes/origin/reports       # never fetched the branch
  mkdir -p "$fresh/reports"; _hist h today > "$fresh/reports/history.csv"; echo b > "$fresh/reports/latest.md"
  mv "$remote" "$remote.gone"
  out="$(bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md 2>&1)"; rc=$?
  assert_eq "no remote and no copy of the branch: exit 5" "$rc" "5"
  assert_contains "and says nothing was committed" "$out" "nothing was committed"
  assert_eq "no local branch was started" "$(git -C "$fresh" for-each-ref refs/heads/reports | wc -l | tr -d ' ')" "0"
  mv "$remote.gone" "$remote"
  bash "$PUB" --restore -C "$fresh" -k reports/history.csv reports >/dev/null 2>&1
  bash "$PUB" -C "$fresh" -k reports/history.csv reports reports/latest.md >/dev/null 2>&1; rc=$?
  assert_eq "with the remote back, restore then publish succeeds" "$rc" "0"
  assert_eq "and the trend is whole" "$(_rshow "$remote" reports/history.csv | tr '\n' ' ')" "h r1 r2 today "
}

# --- the sweep on a checkout with no history of its own --------------------------
# A company on main with its config (reports_branch set) pushed, so a second
# clone is a working company too. Echoes "<co> <remote>".
_sweep_fixture_on_main() {
  local co remote; read -r co remote < <(_sweep_fixture)
  git -C "$co" checkout -q main 2>/dev/null || git -C "$co" checkout -q -
  { echo "reports_branch: reports"; echo "reports_cumulative:   # files that only grow"; echo "  - reports/runs.csv"; } >> "$co/orchestrator.yaml"
  printf 'reports/\n' > "$co/.gitignore"
  git -C "$co" add -A; git -C "$co" commit -q -m "publish reports to a branch"
  git -C "$co" push -q origin HEAD:main
  printf '%s %s\n' "$co" "$remote"
}

t_sweep_from_a_fresh_clone_keeps_the_trend() {
  local co remote fresh out; read -r co remote < <(_sweep_fixture_on_main)
  mkdir -p "$co/reports"; _hist "run,ok" "1,yes" > "$co/reports/runs.csv"
  runco "$co" sweep >/dev/null 2>&1; runco "$co" sweep >/dev/null 2>&1
  assert_eq "fixture: two sweeps published two rows" "$(git -C "$remote" show reports:reports/history.csv | wc -l | tr -d ' ')" "3"
  fresh="$(_fresh_clone "$remote")"
  assert_eq "fixture: the fresh clone has no report files" "$([ -e "$fresh/reports/history.csv" ] && echo yes || echo no)" "no"
  out="$(runco "$fresh" sweep 2>&1)"
  assert_contains "the sweep restores before it generates" "$out" "restored reports/history.csv"
  assert_contains "and publishes" "$out" "published"
  assert_eq "the trend grew by one row, it was not replaced" "$(git -C "$remote" show reports:reports/history.csv | wc -l | tr -d ' ')" "4"
  assert_eq "a reports_cumulative file the fresh clone never wrote is still on the board" \
    "$(git -C "$remote" show reports:reports/runs.csv 2>/dev/null | tr '\n' ' ')" "run,ok 1,yes "
}

t_sweep_log_as_a_cumulative_file_survives_a_fresh_clone() {
  # A company may publish its own sweep log. Cron appends the sweep's output to
  # it while the sweep restores it, and with the clock frozen every run logs the
  # same heading: this run's lines cannot be told from published ones by text.
  local co remote fresh frozen was; read -r co remote < <(_sweep_fixture_on_main)
  echo "  - reports/sweep.log" >> "$co/orchestrator.yaml"
  git -C "$co" add -A; git -C "$co" commit -q -m "publish the sweep log"; git -C "$co" push -q origin HEAD:main
  frozen="$(mktemp -d)"
  printf '#!/bin/sh\ncase "$*" in *%%T*) echo "2026-01-01 08:23:00";; *) echo "2026-01-01";; esac\n' > "$frozen/date"; chmod +x "$frozen/date"
  _cron() { mkdir -p "$1/reports"; ( cd "$1" && PATH="$frozen:$PATH" "$ORCH_BIN" sweep >> reports/sweep.log 2>&1 ); }
  _cron "$co"; _cron "$co"
  assert_eq "fixture: both runs are in the published log" "$(git -C "$remote" show reports:reports/sweep.log | grep -c '^=== sweep')" "2"
  was="$(mktemp)"; git -C "$remote" show reports:reports/sweep.log > "$was"
  fresh="$(_fresh_clone "$remote")"
  _cron "$fresh"
  assert_eq "the log kept the two older runs and gained this one" "$(git -C "$remote" show reports:reports/sweep.log | grep -c '^=== sweep')" "3"
  assert_ok "the log as it was published before is intact at the start of the new one" \
    bash -c 'git -C "$1" show reports:reports/sweep.log | head -c "$(wc -c < "$2")" | cmp -s - "$2"' _ "$remote" "$was"
  assert_eq "and the trend has all three rows" "$(git -C "$remote" show reports:reports/history.csv | wc -l | tr -d ' ')" "4"
}

t_sweep_after_the_pull_that_untracks_the_reports() {
  # The migration itself: reports tracked on main, then the commit that
  # untracks them arrives by pull and git deletes the local copies.
  local root co remote other; root="$(mktemp -d)"; mkrepo "$root" app
  co="$(mkcompany "$root" app:product)"; remote="$(mktemp -d)/remote.git"
  git init -q --bare -b main "$remote"
  git -C "$co" checkout -q -b main 2>/dev/null
  mkdir -p "$co/reports"
  _hist "date,ok,warn,fail,state" "2026-01-01,1,0,0,GREEN" "2026-01-02,1,0,0,GREEN" > "$co/reports/history.csv"
  _hist "run,ok" "1,yes" "2,yes" > "$co/reports/runs.csv"
  echo "old board" > "$co/reports/latest.md"
  git -C "$co" add -A; git -C "$co" commit -q -m "reports tracked on main"
  git -C "$co" remote add origin "$remote"; git -C "$co" push -q -u origin main
  # Seed the reports branch from the tracked copies, as the migration does.
  bash "$PUB" -C "$co" -k reports/history.csv -k reports/runs.csv daily-reports reports/latest.md >/dev/null 2>&1
  # The migration PR, made and merged elsewhere.
  other="$(_fresh_clone "$remote")"
  { echo "reports_branch: daily-reports"; echo "reports_cumulative:"; echo "  - reports/runs.csv"; } >> "$other/orchestrator.yaml"
  git -C "$other" rm -q -r --cached reports; printf 'reports/\n' > "$other/.gitignore"
  git -C "$other" add -A; git -C "$other" commit -q -m "untrack generated reports"; git -C "$other" push -q origin HEAD:main
  git -C "$co" pull -q --ff-only origin main 2>/dev/null
  assert_eq "fixture: the pull deleted the local trend" "$([ -e "$co/reports/history.csv" ] && echo yes || echo no)" "no"
  assert_eq "fixture: and the local run log" "$([ -e "$co/reports/runs.csv" ] && echo yes || echo no)" "no"
  runco "$co" sweep >/dev/null 2>&1
  assert_eq "after the migration the trend still has its old rows plus today's" \
    "$(git -C "$remote" show daily-reports:reports/history.csv | wc -l | tr -d ' ')" "4"
  assert_eq "the first old row is still first" "$(git -C "$remote" show daily-reports:reports/history.csv | sed -n 2p)" "2026-01-01,1,0,0,GREEN"
  assert_eq "the run log is still on the board, whole" "$(git -C "$remote" show daily-reports:reports/runs.csv 2>/dev/null | tr '\n' ' ')" "run,ok 1,yes 2,yes "
  assert_eq "main did not move" "$(git -C "$remote" rev-list --count main)" "2"
}

t_sweep_shouts_when_history_cannot_be_restored() {
  local co remote out; read -r co remote < <(_sweep_fixture_on_main)
  git -C "$co" fetch -q origin; git -C "$co" remote set-head origin main >/dev/null
  mv "$remote" "$remote.gone"
  out="$(runco "$co" sweep 2>&1)"
  assert_contains "an unreachable remote at restore time is loud" "$out" "ATTENTION: could not bring the history files up to date"
  mv "$remote.gone" "$remote"
}

t_sweep_reports_publish_header_may_carry_a_comment() {
  local co remote; read -r co remote < <(_sweep_fixture)
  { echo "reports_branch: reports"; echo "reports_publish:            # optional: more files to publish with them"; echo "  - reports/extra.csv"; } >> "$co/orchestrator.yaml"
  mkdir -p "$co/reports"; echo "a,b" > "$co/reports/extra.csv"
  runco "$co" sweep >/dev/null 2>&1
  assert_eq "a commented section header does not drop the list" "$(git -C "$remote" show reports:reports/extra.csv 2>/dev/null)" "a,b"
}
