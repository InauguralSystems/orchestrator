#!/usr/bin/env bash
# `orchestrator dashboard` — reports/ rendered into one self-contained HTML
# file: KPI parsing, the history chart, escaping at the report boundary, and
# the embedded subsidiary panel (rollup-not-rescore, like health.sh).

# mkreports DIR STATE — a minimal health report + history in DIR/reports
mkreports() {
  mkdir -p "$1/reports"
  cat > "$1/reports/latest.md" <<EOF
# Fixture health — 2026-07-09

| Repo | Cat | Status |
|---|---|---|
| core | product | **OK** |
| web | consumer | **WARN** — dirty tree |

## Summary

- Active repos: OK=1 WARN=1 FAIL=0 → **$2**
- Skills: live tree and committed copy in sync
EOF
  cat > "$1/reports/history.csv" <<EOF
date,ok,warn,fail,state
2026-07-08,2,0,0,GREEN
2026-07-09,1,1,0,$2
EOF
}

t_dashboard_renders_reports() {
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "core"
  local co; co="$(mkcompany "$root" "core:product")"
  mkreports "$co" GREEN
  echo "standup body marker" > "$co/reports/standup_latest.md"
  local out; out="$(runco "$co" dashboard)"
  assert_contains "dashboard prints the output path" "$out" "reports/dashboard.html"
  assert_file "dashboard.html is written" "$co/reports/dashboard.html"
  local html; html="$(cat "$co/reports/dashboard.html")"
  assert_contains "company name is the title" "$html" "TestCo"
  assert_contains "verdict chip is rendered" "$html" ">GREEN</span>"
  assert_contains "repo table row survives" "$html" "<td>core</td>"
  assert_contains "status why-text survives" "$html" "dirty tree"
  assert_contains "history renders chart columns" "$html" "class=\"col\""
  assert_contains "chart tooltip carries the counts" "$html" "OK 1 &middot; WARN 1 &middot; FAIL 0"
  assert_contains "standup digest is embedded" "$html" "standup body marker"
}

t_dashboard_subsidiary_panel() {
  # A subsidiary's panel renders from the CHILD's own reports/ — including a
  # child history.csv with EXTRA columns (pins, tag), which land in the tooltip.
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "child"
  mkdir -p "$root/child/reports"
  cat > "$root/child/reports/latest.md" <<'EOF'
# Child health — 2026-07-09

| Repo | Cat | Status |
|---|---|---|
| lib | product | **OK** |

## Summary

- Active repos: OK=1 WARN=0 FAIL=0 → **GREEN**
EOF
  cat > "$root/child/reports/history.csv" <<'EOF'
date,ok,warn,fail,pins_current,latest_tag,state
2026-07-09,15,0,0,10/10,v0.28.0,GREEN
EOF
  local co; co="$(mkcompany "$root" "child:subsidiary")"
  mkreports "$co" YELLOW
  runco "$co" dashboard >/dev/null
  local html; html="$(cat "$co/reports/dashboard.html")"
  assert_contains "subsidiary panel is embedded" "$html" "Subsidiary — child"
  assert_contains "child verdict rolls up from its own report" "$html" ">GREEN</span>"
  assert_contains "child extra history columns land in the tooltip" "$html" "pins 10/10 &middot; v0.28.0"
}

t_dashboard_no_reports_yet() {
  # A fresh company (no health run) still renders — with an honest note, not
  # a broken page or a nonzero exit.
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "core"
  local co; co="$(mkcompany "$root" "core:product")"
  assert_ok "dashboard exits 0 with no reports" runco "$co" dashboard
  local html; html="$(cat "$co/reports/dashboard.html")"
  assert_contains "missing report is an explicit note" "$html" "No health report yet"
}

t_dashboard_escapes_report_html() {
  # The reports are a trust boundary: a repo name / why-text containing markup
  # must not become live HTML in the dashboard.
  local root; root="$(mkroot_dir)"
  mkrepo "$root" "core"
  local co; co="$(mkcompany "$root" "core:product")"
  mkreports "$co" GREEN
  cat >> "$co/reports/latest.md" <<'EOF'
- note with <script>alert(1)</script> inside
EOF
  runco "$co" dashboard >/dev/null
  local html; html="$(cat "$co/reports/dashboard.html")"
  assert_missing  "raw script tag never survives" "$html" "<script>"
  assert_contains "markup is escaped, not dropped" "$html" "&lt;script&gt;"
}
