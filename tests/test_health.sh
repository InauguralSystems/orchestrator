#!/usr/bin/env bash
# health --local: scores repos, writes the report + trend, and its exit code.

t_health_green_and_reports() {
  local root; root="$(mktemp -d)"; mkrepo "$root" acme-core
  echo MIT > "$root/acme-core/LICENSE"                # a clean repo carries a license
  git -C "$root/acme-core" add .; git -C "$root/acme-core" commit -q -m license
  local co; co="$(mkcompany "$root" "acme-core:product")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "clean repo scores OK"   "$out" "**OK**"
  assert_contains "company comes up GREEN" "$out" "GREEN"
  assert_ok       "health exits 0 on GREEN" bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1"
  assert_file     "writes reports/latest.md"  "$co/reports/latest.md"
  assert_file     "appends reports/history.csv" "$co/reports/history.csv"
}

t_health_flags_missing_repo() {
  local root; root="$(mktemp -d)"           # empty root — repo not cloned
  local co; co="$(mkcompany "$root" "ghost:consumer")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "uncloned repo warns" "$out" "not cloned"
}

t_health_parked_not_scored() {
  local root; root="$(mktemp -d)"
  local co; co="$(mkcompany "$root" "gone:parked")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "parked repo not a WARN/FAIL" "$out" "parked"
}

t_health_warns_absent_ci() {  # G9: no CI configured must WARN, not read as green
  local root; root="$(mktemp -d)"; mkrepo "$root" nocirepo
  git -C "$root/nocirepo" remote add origin https://github.com/acme/nocirepo
  echo MIT > "$root/nocirepo/LICENSE"    # license present, so the only gap is CI
  git -C "$root/nocirepo" add .; git -C "$root/nocirepo" commit -q -m license
  local co; co="$(mkcompany "$root" "nocirepo:consumer")"
  # fake gh on PATH: report zero workflow runs ("-") + an open count, no network.
  local fakebin; fakebin="$(mktemp -d)"
  { echo '#!/usr/bin/env bash'
    echo 'case "$*" in *"run list"*) echo "-";; *"api"*) echo 3;; *) exit 0;; esac'
  } > "$fakebin/gh"; chmod +x "$fakebin/gh"
  local out; out="$(cd "$co" && PATH="$fakebin:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_contains "absent CI warns"          "$out" "no CI configured"
  assert_contains "absent-CI repo is WARN"   "$out" "**WARN**"
}

# _fakegh DIR PRIVATE — write a fake `gh` into DIR that reports green CI and
# repo_meta "OPEN PRIVATE" with the given private flag (true/false), no network.
_fakegh() {
  { echo '#!/usr/bin/env bash'
    echo "case \"\$*\" in *\"run list\"*) echo success;; *\"api\"*) echo \"0 $2\";; *) exit 0;; esac"
  } > "$1/gh"; chmod +x "$1/gh"
}

t_health_governance_counts_present_standards() {
  local root; root="$(mktemp -d)"; mkrepo "$root" good
  echo r > "$root/good/README.md"; echo MIT > "$root/good/LICENSE"; echo s > "$root/good/SECURITY.md"
  git -C "$root/good" add .; git -C "$root/good" commit -q -m standards
  local co; co="$(mkcompany "$root" "good:consumer")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "counts the three present standards" "$out" "3/5"
}

t_health_governance_public_missing_license_warns() {  # G4: public repo, no LICENSE -> WARN
  local root; root="$(mktemp -d)"; mkrepo "$root" pub
  git -C "$root/pub" remote add origin https://github.com/acme/pub
  local co; co="$(mkcompany "$root" "pub:consumer")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" false      # public
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_contains "governance column present (0/5)" "$out" "0/5"
  assert_contains "public repo missing LICENSE warns" "$out" "missing LICENSE"
}

t_health_governance_private_repo_no_license_ok() {  # a private repo needs no license
  local root; root="$(mktemp -d)"; mkrepo "$root" priv
  git -C "$root/priv" remote add origin https://github.com/acme/priv
  local co; co="$(mkcompany "$root" "priv:consumer")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" true       # private
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_missing "private repo not flagged for missing LICENSE" "$out" "missing LICENSE"
}

t_health_governance_exempts_sibling() {  # sibling exempt even when public + no LICENSE
  local root; root="$(mktemp -d)"; mkrepo "$root" sib
  git -C "$root/sib" remote add origin https://github.com/acme/sib
  local co; co="$(mkcompany "$root" "sib:sibling")"
  local fb; fb="$(mktemp -d)"; _fakegh "$fb" false      # public, yet a sibling
  local out; out="$(cd "$co" && PATH="$fb:$PATH" "$ORCH_BIN" health 2>&1)"
  assert_missing "sibling is exempt from the missing-LICENSE warn" "$out" "missing LICENSE"
}

t_health_subsidiary_rolls_up_green_child() {  # a subsidiary surfaces its child's OWN verdict
  local root; root="$(mktemp -d)"; mkrepo "$root" childco
  mkdir -p "$root/childco/reports"
  printf -- '- Active repos: OK=5 WARN=0 FAIL=0 -> **GREEN**\n' > "$root/childco/reports/latest.md"
  printf 'date,ok,warn,fail,state\n%s,5,0,0,GREEN\n' "$(date +%F)" > "$root/childco/reports/history.csv"
  git -C "$root/childco" add .; git -C "$root/childco" commit -q -m report
  local co; co="$(mkcompany "$root" "childco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "subsidiary shows the rolled-up child verdict" "$out" "**GREEN** — subsidiary roll-up"
  assert_contains "a fresh GREEN child keeps the parent GREEN"    "$out" "→ **GREEN**"
}

t_health_subsidiary_stale_green_downgraded() {  # a stale self-reported GREEN must not read as fresh
  local root; root="$(mktemp -d)"; mkrepo "$root" staleco
  mkdir -p "$root/staleco/reports"
  printf -- '- Active repos: OK=5 WARN=0 FAIL=0 -> **GREEN**\n' > "$root/staleco/reports/latest.md"
  printf 'date,ok,warn,fail,state\n2000-01-01,5,0,0,GREEN\n' > "$root/staleco/reports/history.csv"
  git -C "$root/staleco" add .; git -C "$root/staleco" commit -q -m stale
  local co; co="$(mkcompany "$root" "staleco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a stale subsidiary GREEN drops to WARN" "$out" "**WARN**"
  assert_contains "the staleness is explained"            "$out" "stale"
}

t_health_subsidiary_stale_red_not_hidden() {  # staleness must never hide a known failure
  local root; root="$(mktemp -d)"; mkrepo "$root" sickold
  mkdir -p "$root/sickold/reports"
  printf -- '- Active repos: OK=0 WARN=0 FAIL=3 -> **RED**\n' > "$root/sickold/reports/latest.md"
  printf 'date,ok,warn,fail,state\n2000-01-01,0,0,3,RED\n' > "$root/sickold/reports/history.csv"
  git -C "$root/sickold" add .; git -C "$root/sickold" commit -q -m stalered
  local co; co="$(mkcompany "$root" "sickold:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a stale RED is not hidden — stays RED" "$out" "**RED**"
}

t_health_subsidiary_red_child_fails_parent() {  # a RED child must make the parent RED (exit 1)
  local root; root="$(mktemp -d)"; mkrepo "$root" sickco
  mkdir -p "$root/sickco/reports"
  printf -- '- Active repos: OK=1 WARN=0 FAIL=2 -> **RED**\n' > "$root/sickco/reports/latest.md"
  git -C "$root/sickco" add .; git -C "$root/sickco" commit -q -m report
  local co; co="$(mkcompany "$root" "sickco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a RED child rolls up as RED" "$out" "**RED** — subsidiary roll-up"
  assert_contains "a RED child turns the parent RED" "$out" "→ **RED**"
  assert_ok "health exits nonzero when a subsidiary is RED" \
    bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1; [ \$? -eq 1 ]"
}

t_health_subsidiary_red_in_motion_annotated() {  # #1: a RED child with recent work reads in-motion
  local root; root="$(mktemp -d)"; mkrepo "$root" busyco   # mkrepo's commit = recent non-report work
  mkdir -p "$root/busyco/reports"
  printf -- '- Active repos: OK=1 WARN=0 FAIL=2 -> **RED**\n' > "$root/busyco/reports/latest.md"
  printf 'date,ok,warn,fail,state\n%s,1,0,2,RED\n' "$(date +%F)" > "$root/busyco/reports/history.csv"
  git -C "$root/busyco" add .; git -C "$root/busyco" commit -q -m report
  local co; co="$(mkcompany "$root" "busyco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a working RED child is annotated in motion" "$out" "in motion:"
  assert_contains "the RED run length is surfaced"             "$out" "RED 1d running"
  assert_ok "an in-motion RED still fails the parent (exit 1)" \
    bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1; [ \$? -eq 1 ]"
}

t_health_subsidiary_red_stalled_annotated() {  # #1: a RED child with no real work reads STALLED
  local root; root="$(mktemp -d)"; local d="$root/deadco"; mkdir -p "$d"; _gitinit "$d"
  echo x > "$d/f"; git -C "$d" add .
  GIT_AUTHOR_DATE='2000-01-01T00:00:00' GIT_COMMITTER_DATE='2000-01-01T00:00:00' \
    git -C "$d" commit -q -m init                     # the only non-report commit is ancient
  mkdir -p "$d/reports"
  printf -- '- Active repos: OK=0 WARN=0 FAIL=3 -> **RED**\n' > "$d/reports/latest.md"
  printf 'date,ok,warn,fail,state\n%s,0,0,3,RED\n%s,0,0,3,RED\n' "$(date +%F)" "$(date +%F)" \
    > "$d/reports/history.csv"
  git -C "$d" add reports; git -C "$d" commit -q -m sweep   # recent but reports-only — excluded
  local co; co="$(mkcompany "$root" "deadco:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a workless RED child is annotated STALLED"  "$out" "STALLED:"
  assert_contains "the RED run counts consecutive RED entries" "$out" "RED 2d running"
  assert_missing "a stalled child is not called in motion"     "$out" "in motion:"
}

t_health_own_reports_churn_not_dirty() {  # the instrument's own reports/ writes must not self-WARN
  local root; root="$(mktemp -d)"; mkrepo "$root" selfco
  local live; live="$(mktemp -d)"
  local co="$root/selfco"                   # the company home IS a scored repo (the Meta layout)
  { echo "company: TestCo"; echo "ceo: T"; echo "github_org:"
    echo "root: $root"; echo "live_skills: $live"; echo "skills_dir: skills"
    echo "repos:"; echo "  - selfco:sibling"
    echo "vetoes:"; echo "  - No test left red."
  } > "$co/orchestrator.yaml"
  mkdir -p "$co/skills" "$co/reports"
  echo old > "$co/reports/latest.md"
  git -C "$co" add .; git -C "$co" commit -q -m config
  local out; out="$(runco "$co" health --local 2>&1)"   # health rewrites reports/ mid-run
  assert_missing "own reports/ churn is not a dirty tree" "$out" "dirty tree"
  echo w > "$co/wip"                        # a real uncommitted file must still warn
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "real working changes still warn dirty" "$out" "dirty tree"
}

t_health_subsidiary_missing_report_warns() {  # no child report to roll up -> WARN, never silent-OK
  local root; root="$(mktemp -d)"; mkrepo "$root" noreport
  local co; co="$(mkcompany "$root" "noreport:subsidiary")"
  local out; out="$(runco "$co" health --local 2>&1)"
  assert_contains "a subsidiary with no health report warns" "$out" "no subsidiary health report"
}

# --- a subsidiary that publishes its reports to a branch ------------------------
# The child keeps no report files on its default branch, so a parent reading a
# clone that never ran the child's sweep has nothing on disk. Before this, a
# published RED read as "no subsidiary health report" and the parent stayed GREEN.
# _published_child ROOT NAME STATE DATE [yaml] — a child repo whose checkout has
# no reports/, with origin/daily-reports holding a STATE board dated DATE.
_published_child() {
  local root="$1" name="$2" state="$3" date="$4" yaml="${5:-yes}" remote
  remote="$(mktemp -d)/$name.git"; git init -q --bare -b main "$remote"
  mkrepo "$root" "$name"
  [ "$yaml" = yes ] && { echo "reports_branch: daily-reports" > "$root/$name/orchestrator.yaml"; git -C "$root/$name" add -A; git -C "$root/$name" commit -q -m config; }
  git -C "$root/$name" branch -M main; git -C "$root/$name" remote add origin "$remote"
  git -C "$root/$name" push -q -u origin main
  mkdir -p "$root/$name/reports"
  printf -- '- Active repos: OK=1 WARN=0 FAIL=2 -> **%s**\n' "$state" > "$root/$name/reports/latest.md"
  printf 'date,ok,warn,fail,state\n%s,1,0,2,%s\n' "$date" "$state" > "$root/$name/reports/history.csv"
  bash "$PRODUCT/tools/publish_reports.sh" -C "$root/$name" -k reports/history.csv daily-reports reports/latest.md >/dev/null 2>&1
  rm -rf "$root/$name/reports"                                   # this clone never ran the sweep
  git -C "$root/$name" branch -q -D daily-reports 2>/dev/null     # and only knows origin's copy
}

t_health_subsidiary_read_from_its_reports_branch() {
  local root co out; root="$(mktemp -d)"
  _published_child "$root" sickco RED "$(date +%F)"
  assert_ok "fixture: the board is only on origin/daily-reports" \
    bash -c "[ ! -e '$root/sickco/reports' ] && git -C '$root/sickco' cat-file -e origin/daily-reports:reports/latest.md"
  co="$(mkcompany "$root" "sickco:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "a RED published to the child's reports branch rolls up" "$out" "**RED** — subsidiary roll-up"
  assert_missing "and is not reported as a missing report" "$out" "no subsidiary health report"
  assert_ok "the parent exits nonzero" bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1; [ \$? -eq 1 ]"
}

t_health_subsidiary_branch_named_by_the_parent() {
  # A child that runs its own tooling has no orchestrator.yaml to say where.
  local root co out; root="$(mktemp -d)"
  _published_child "$root" owntools RED "$(date +%F)" no
  co="$(mkcompany "$root" "owntools:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "without the parent's setting the board is not found" "$out" "no subsidiary health report"
  echo "subsidiary_reports_branch: daily-reports" >> "$co/orchestrator.yaml"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "with it, the RED rolls up" "$out" "**RED** — subsidiary roll-up"
}

t_health_subsidiary_newer_copy_wins() {
  local root co out; root="$(mktemp -d)"
  _published_child "$root" kid GREEN "2026-01-01"
  co="$(mkcompany "$root" "kid:subsidiary")"
  # The checkout ran a sweep today whose publish failed: its files are newer.
  mkdir -p "$root/kid/reports"
  printf -- '- Active repos: OK=0 WARN=0 FAIL=3 -> **RED**\n' > "$root/kid/reports/latest.md"
  printf 'date,ok,warn,fail,state\n%s,0,0,3,RED\n' "$(date +%F)" > "$root/kid/reports/history.csv"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "newer checkout files beat an older branch" "$out" "**RED** — subsidiary roll-up"
  # A leftover file older than the branch must not hide the published verdict.
  printf -- '- Active repos: OK=3 WARN=0 FAIL=0 -> **GREEN**\n' > "$root/kid/reports/latest.md"
  printf 'date,ok,warn,fail,state\n2025-12-01,3,0,0,GREEN\n' > "$root/kid/reports/history.csv"
  local stage; stage="$(mktemp -d)/kid2"; git clone -q "$(git -C "$root/kid" remote get-url origin)" "$stage" 2>/dev/null; _gitinit "$stage"
  mkdir -p "$stage/reports"; printf -- '- Active repos: OK=0 WARN=0 FAIL=1 -> **RED**\n' > "$stage/reports/latest.md"
  printf 'date,ok,warn,fail,state\n2026-01-01,1,0,2,GREEN\n%s,0,0,1,RED\n' "$(date +%F)" > "$stage/reports/history.csv"
  bash "$PRODUCT/tools/publish_reports.sh" -C "$stage" -k reports/history.csv daily-reports reports/latest.md >/dev/null 2>&1
  git -C "$root/kid" fetch -q origin
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "a newer branch beats leftover checkout files" "$out" "**RED** — subsidiary roll-up"
}

# --- which copy of a subsidiary's board is newer --------------------------------
# Found in review: dates alone cannot order two boards from the same day, and
# commit timestamps cannot order two branch tips made in the same second. In
# both cases the parent showed GREEN while a newer published board was RED.
# _board DIR STATE ROWS... — write latest.md (STATE) and history.csv (header + ROWS) in DIR/reports
_board() {
  local d="$1" st="$2"; shift 2; mkdir -p "$d/reports"
  printf -- '- Active repos: OK=1 WARN=0 FAIL=0 -> **%s**\n' "$st" > "$d/reports/latest.md"
  { echo "date,ok,warn,fail,state"; printf '%s\n' "$@"; } > "$d/reports/history.csv"
}
_pub_board() { bash "$PRODUCT/tools/publish_reports.sh" -C "$1" -k reports/history.csv daily-reports reports/latest.md >/dev/null 2>&1; }
# A child with config and an origin, nothing published. Echoes nothing; $root/$name is the checkout.
_child_with_origin() {
  local root="$1" name="$2" remote; remote="$(mktemp -d)/$name.git"; git init -q --bare -b main "$remote"
  mkrepo "$root" "$name"; echo "reports_branch: daily-reports" > "$root/$name/orchestrator.yaml"
  git -C "$root/$name" add -A; git -C "$root/$name" commit -q -m config
  git -C "$root/$name" branch -M main; git -C "$root/$name" remote add origin "$remote"; git -C "$root/$name" push -q -u origin main
}

t_health_subsidiary_same_day_newer_published_red_is_not_hidden() {
  local root co out today other; root="$(mktemp -d)"; today="$(date +%F)"
  _child_with_origin "$root" kid
  # This checkout swept this morning: GREEN, published.
  _board "$root/kid" GREEN "$today,1,0,0,GREEN"; _pub_board "$root/kid"
  # Another machine swept later the same day: RED, published on top.
  other="$(mktemp -d)/other"; git clone -q "$(git -C "$root/kid" remote get-url origin)" "$other" 2>/dev/null; _gitinit "$other"
  _board "$other" RED "$today,1,0,0,GREEN" "$today,0,0,1,RED"; _pub_board "$other"
  git -C "$root/kid" fetch -q origin
  assert_eq "fixture: the checkout still says GREEN" "$(grep -oE 'GREEN|RED' "$root/kid/reports/latest.md" | tail -1)" "GREEN"
  assert_eq "fixture: the published board says RED" "$(git -C "$root/kid" show origin/daily-reports:reports/latest.md | grep -oE 'GREEN|RED' | tail -1)" "RED"
  co="$(mkcompany "$root" "kid:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "a later same-day RED on the branch beats the checkout's GREEN" "$out" "**RED** — subsidiary roll-up"
  assert_ok "and the parent exits nonzero" bash -c "cd '$co' && '$ORCH_BIN' health --local >/dev/null 2>&1; [ \$? -eq 1 ]"
  # Later still, the other machine publishes the fix. The checkout is now the
  # stale RED one: order comes from the history, not from which verdict is worse.
  _board "$root/kid" RED "$today,1,0,0,GREEN" "$today,0,0,1,RED"
  _board "$other" GREEN "$today,1,0,0,GREEN" "$today,0,0,1,RED" "$today,2,0,0,GREEN"; _pub_board "$other"
  git -C "$root/kid" fetch -q origin
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "a later same-day GREEN on the branch beats the checkout's stale RED" "$out" "**GREEN** — subsidiary roll-up"
}

t_health_subsidiary_same_day_checkout_ahead_of_branch_wins() {
  # The mirror case: this checkout swept again and its publish failed. Its
  # history extends the published one, so it is the newer board.
  local root co out today; root="$(mktemp -d)"; today="$(date +%F)"
  _child_with_origin "$root" kid
  _board "$root/kid" RED "$today,0,0,1,RED"; _pub_board "$root/kid"
  _board "$root/kid" GREEN "$today,0,0,1,RED" "$today,1,0,0,GREEN"          # fixed, not yet published
  co="$(mkcompany "$root" "kid:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "a checkout whose history extends the branch's is the newer board" "$out" "**GREEN** — subsidiary roll-up"
}

t_health_subsidiary_unorderable_same_day_shows_the_failure() {
  # Two boards from the same day with unrelated histories cannot be ordered.
  # Then the failing one is shown: a known failure is never hidden.
  local root co out today other; root="$(mktemp -d)"; today="$(date +%F)"
  _child_with_origin "$root" kid
  other="$(mktemp -d)/other"; git clone -q "$(git -C "$root/kid" remote get-url origin)" "$other" 2>/dev/null; _gitinit "$other"
  _board "$other" RED "$today,0,0,1,RED"; _pub_board "$other"
  git -C "$root/kid" fetch -q origin
  _board "$root/kid" GREEN "$today,1,0,0,GREEN"
  co="$(mkcompany "$root" "kid:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "branch RED vs checkout GREEN, same day, unrelated: RED" "$out" "**RED** — subsidiary roll-up"
  # And the other way round.
  _board "$root/kid" RED "$today,0,0,2,RED"
  _board "$other" GREEN "$today,0,0,1,RED" "$today,3,0,0,GREEN"; _pub_board "$other"
  git -C "$root/kid" fetch -q origin
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "checkout RED vs branch GREEN, same day, unrelated: RED" "$out" "**RED** — subsidiary roll-up"
}

t_health_subsidiary_descendant_tip_wins_a_timestamp_tie() {
  # Local branch tip and origin's tip made in the same second; origin's is the
  # descendant. Sorting by commit time cannot tell them apart.
  local root co out today other when; root="$(mktemp -d)"; today="$(date +%F)"; when="2026-01-02T08:23:00Z"
  _child_with_origin "$root" kid
  _board "$root/kid" GREEN "2026-01-02,1,0,0,GREEN"
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" _pub_board "$root/kid"       # local tip == origin tip
  other="$(mktemp -d)/other"; git clone -q "$(git -C "$root/kid" remote get-url origin)" "$other" 2>/dev/null; _gitinit "$other"
  _board "$other" RED "2026-01-02,1,0,0,GREEN" "$today,0,0,1,RED"
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" _pub_board "$other"           # descendant, same second
  git -C "$root/kid" fetch -q origin
  rm -rf "$root/kid/reports"                                                       # only the branch copies remain
  assert_eq "fixture: the two tips differ" "$([ "$(git -C "$root/kid" rev-parse daily-reports)" != "$(git -C "$root/kid" rev-parse origin/daily-reports)" ] && echo yes)" "yes"
  assert_eq "fixture: and carry the same commit time" "$(git -C "$root/kid" log -1 --format=%ct daily-reports)" "$(git -C "$root/kid" log -1 --format=%ct origin/daily-reports)"
  assert_ok "fixture: origin's tip descends from the local one" git -C "$root/kid" merge-base --is-ancestor daily-reports origin/daily-reports
  co="$(mkcompany "$root" "kid:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "the descendant tip is read, whichever ref holds it" "$out" "**RED** — subsidiary roll-up"
  # Mirror: the LOCAL tip is the descendant (a publish queued, not yet pushed).
  git -C "$root/kid" update-ref refs/remotes/origin/daily-reports "$(git -C "$root/kid" rev-parse daily-reports)"
  git -C "$root/kid" update-ref refs/heads/daily-reports "$(git -C "$other" rev-parse daily-reports)"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "and the same when the local ref holds the descendant" "$out" "**RED** — subsidiary roll-up"
}

t_health_subsidiary_descendant_tip_wins_against_a_skewed_clock() {
  # The older tip was committed by a machine whose clock runs ahead, so its
  # commit time is LATER than its descendant's. Ancestry, not time, decides.
  local root co out today other; root="$(mktemp -d)"; today="$(date +%F)"
  _child_with_origin "$root" kid
  _board "$root/kid" GREEN "2026-01-02,1,0,0,GREEN"
  GIT_COMMITTER_DATE="2026-01-02T09:00:00Z" GIT_AUTHOR_DATE="2026-01-02T09:00:00Z" _pub_board "$root/kid"
  other="$(mktemp -d)/other"; git clone -q "$(git -C "$root/kid" remote get-url origin)" "$other" 2>/dev/null; _gitinit "$other"
  _board "$other" RED "2026-01-02,1,0,0,GREEN" "$today,0,0,1,RED"
  GIT_COMMITTER_DATE="2026-01-02T08:00:00Z" GIT_AUTHOR_DATE="2026-01-02T08:00:00Z" _pub_board "$other"
  git -C "$root/kid" fetch -q origin; rm -rf "$root/kid/reports"
  assert_ok "fixture: origin's tip descends from the local one" git -C "$root/kid" merge-base --is-ancestor daily-reports origin/daily-reports
  assert_eq "fixture: yet the local tip has the later commit time" \
    "$([ "$(git -C "$root/kid" log -1 --format=%ct daily-reports)" -gt "$(git -C "$root/kid" log -1 --format=%ct origin/daily-reports)" ] && echo yes)" "yes"
  co="$(mkcompany "$root" "kid:subsidiary")"
  out="$(runco "$co" health --local 2>&1)"
  assert_contains "the descendant is read although its commit time is earlier" "$out" "**RED** — subsidiary roll-up"
}
