#!/usr/bin/env bash
# dashboard.sh — render the company's reports into ONE self-contained HTML
# dashboard: reports/dashboard.html. Read-only over the portfolio (it renders
# what health/standup already measured — it never re-scores); writes only the
# dashboard file. Subsidiaries get an embedded section rendered from the child
# company's own reports/ — same rollup-not-rescore rule as health.sh.
# Usage: tools/dashboard.sh   (via `orchestrator dashboard`)
set -u

PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PRODUCT/lib/config.sh" || exit 1

ROOT="$(orch_expand "$(orch_get root)")"
COMPANY="$(orch_get company Company)"
mkdir -p "$ORCH_HOME/reports"
OUT="$ORCH_HOME/reports/dashboard.html"

_esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# _kpis LATEST — echo "STATE OK WARN FAIL DATE" parsed from a health report.
# Same conventions health.sh's subsidiary rollup relies on: the last
# GREEN|YELLOW|RED in the file is the verdict; the Active-repos line has counts.
_kpis() {
  local state counts d
  state="$(grep -oE 'GREEN|YELLOW|RED' "$1" 2>/dev/null | tail -1)"
  counts="$(sed -n 's/.*OK=\([0-9]*\) WARN=\([0-9]*\) FAIL=\([0-9]*\).*/\1 \2 \3/p' "$1" | head -1)"
  d="$(sed -n '1s/.*— \([0-9-]*\).*/\1/p' "$1")"
  echo "${state:-?} ${counts:-? ? ?} ${d:-?}"
}

# _table_html LATEST — the report's markdown table as an HTML table. Cells are
# escaped; a leading **STATUS** becomes a labeled chip (icon dot + text — the
# status color never carries meaning alone).
_table_html() {
  grep '^|' "$1" | _esc | awk '
    function cell(c,   s, cls, rest) {
      gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (match(c, /^\*\*[A-Za-z!]+\*\*/)) {
        s = substr(c, 3, RLENGTH - 4); rest = substr(c, RLENGTH + 1)
        cls = "muted"
        if (s == "OK" || s == "GREEN")                    cls = "good"
        else if (s == "WARN" || s == "YELLOW")            cls = "warn"
        else if (s == "FAIL" || s == "RED" || s == "parked!") cls = "fail"
        return "<span class=\"chip c-" cls "\"><span class=\"dot\"></span>" s "</span><span class=\"why\">" rest "</span>"
      }
      gsub(/\*\*/, "", c)
      return c
    }
    /^\|[ \t:|-]*\|$/ { next }                       # the |---|---| separator
    {
      n = split($0, f, "|")
      tag = (hdr++ ? "td" : "th")
      row = "<tr>"
      for (i = 2; i < n; i++) row = row "<" tag ">" cell(f[i]) "</" tag ">"
      print row "</tr>"
    }
    BEGIN { print "<div class=\"tablewrap\"><table>" }
    END   { print "</table></div>" }
  '
}

# _notes_html LATEST — the report lines that are neither the table, the title,
# nor the KPI counts line (pins, skills drift, latest tag, --local notice, ...).
_notes_html() {
  grep -v '^|' "$1" | grep -v '^#' | grep -v '^$' | grep -v 'Active repos' \
    | sed 's/^- //' | _esc \
    | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g' \
    | sed 's/^/<li>/; s/$/<\/li>/'
}

# _chart_html HISTORY — stacked columns (OK/WARN/FAIL per run) from history.csv,
# newest 60 runs, with a per-column hover tooltip and first/last date labels.
# Column layout follows the header row, so the parent (5-col) and a child with
# extra columns (pins, tag) both render; extras land in the tooltip.
_chart_html() {
  awk '
    BEGIN { FS = "," }
    NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
    NF < 2 { next }
    {
      n++
      date[n] = $h["date"]; ok[n] = $h["ok"] + 0
      wa[n] = $h["warn"] + 0; fa[n] = $h["fail"] + 0; st[n] = $h["state"]
      ex[n] = ""
      if ("pins_current" in h) ex[n] = " &middot; pins " $h["pins_current"]
      if ("latest_tag" in h)   ex[n] = ex[n] " &middot; " $h["latest_tag"]
      tot = ok[n] + wa[n] + fa[n]; if (tot > max) max = tot
    }
    function seg(cls, hpx, cap) {
      if (hpx < 1) return
      print "      <div class=\"seg s-" cls (cap ? " cap" : "") "\" style=\"height:" hpx "px\"></div>"
    }
    END {
      if (n == 0) { print "<p class=\"note\">No history yet — run <code>orchestrator health</code>.</p>"; exit }
      H = 96; if (max < 1) max = 1
      start = (n > 60) ? n - 59 : 1
      print "<div class=\"chart\">"
      for (i = start; i <= n; i++) {
        fh = int(fa[i] * H / max + 0.5); wh = int(wa[i] * H / max + 0.5); oh = int(ok[i] * H / max + 0.5)
        print "  <div class=\"colwrap\">"
        print "    <div class=\"tip\">" date[i] " &middot; OK " ok[i] " &middot; WARN " wa[i] " &middot; FAIL " fa[i] ex[i] " &middot; " st[i] "</div>"
        print "    <div class=\"col\">"
        seg("fail", fh, 1); seg("warn", wh, fh < 1); seg("ok", oh, fh < 1 && wh < 1)
        print "    </div>"
        print "  </div>"
      }
      print "</div>"
      print "<div class=\"xlab\"><span>" date[start] "</span><span>" date[n] "</span></div>"
      print "<div class=\"legend\">" \
        "<span><span class=\"dot d-ok\"></span>OK</span>" \
        "<span><span class=\"dot d-warn\"></span>WARN</span>" \
        "<span><span class=\"dot d-fail\"></span>FAIL</span></div>"
    }
  ' "$1"
}

# _section TITLE REPORTS_DIR — one company's full panel: KPI tiles, the health
# trend, the repo table, the notes, and the standup digest.
_section() {
  local title="$1" rdir="$2" latest="$2/latest.md"
  echo "<section>"
  echo "<h2>$(printf '%s' "$title" | _esc)</h2>"
  if [ ! -f "$latest" ]; then
    echo "<p class=\"note\">No health report yet — run <code>orchestrator health</code> in this company.</p>"
    echo "</section>"
    return 0
  fi
  local state ok warn fail d
  read -r state ok warn fail d <<EOF
$(_kpis "$latest")
EOF
  local cls="muted"
  case "$state" in GREEN) cls="good";; YELLOW) cls="warn";; RED) cls="fail";; esac
  cat <<EOF
<div class="kpis">
  <div class="tile"><div class="lab">State</div>
    <div class="val"><span class="chip big c-$cls"><span class="dot"></span>$state</span></div>
    <div class="sub">as of $d</div></div>
  <div class="tile"><div class="lab"><span class="dot d-ok"></span>OK</div><div class="val num">$ok</div></div>
  <div class="tile"><div class="lab"><span class="dot d-warn"></span>WARN</div><div class="val num">$warn</div></div>
  <div class="tile"><div class="lab"><span class="dot d-fail"></span>FAIL</div><div class="val num">$fail</div></div>
</div>
<h3>Health trend</h3>
EOF
  if [ -f "$rdir/history.csv" ]; then _chart_html "$rdir/history.csv"
  else echo "<p class=\"note\">No history yet — run <code>orchestrator health</code>.</p>"; fi
  echo "<h3>Repos</h3>"
  _table_html "$latest"
  echo "<ul class=\"notes\">"
  _notes_html "$latest"
  echo "</ul>"
  if [ -f "$rdir/standup_latest.md" ]; then
    echo "<details><summary>Standup — what moved</summary><pre>"
    _esc < "$rdir/standup_latest.md"
    echo "</pre></details>"
  fi
  echo "</section>"
}

{
  cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
EOF
  echo "<title>$(printf '%s' "$COMPANY" | _esc) — dashboard</title>"
  cat <<'EOF'
<style>
:root {
  --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink2: #52514e;
  --muted: #898781; --grid: #e1e0d9; --border: rgba(11,11,11,0.10);
  --good: #0ca30c; --warn: #fab219; --fail: #d03b3b;
}
@media (prefers-color-scheme: dark) {
  :root { --page: #0d0d0d; --surface: #1a1a19; --ink: #ffffff; --ink2: #c3c2b7;
          --grid: #2c2c2a; --border: rgba(255,255,255,0.10); }
}
:root[data-theme="dark"]  { --page: #0d0d0d; --surface: #1a1a19; --ink: #ffffff; --ink2: #c3c2b7;
                            --grid: #2c2c2a; --border: rgba(255,255,255,0.10); }
:root[data-theme="light"] { --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink2: #52514e;
                            --grid: #e1e0d9; --border: rgba(11,11,11,0.10); }
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink);
       font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 980px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { font-size: 22px; margin: 0 0 4px; }
h2 { font-size: 18px; margin: 0 0 12px; }
h3 { font-size: 13px; color: var(--ink2); text-transform: uppercase;
     letter-spacing: .04em; margin: 20px 0 8px; }
.gen { color: var(--muted); font-size: 13px; margin: 0 0 20px; }
section { background: var(--surface); border: 1px solid var(--border);
          border-radius: 10px; padding: 20px; margin: 0 0 20px; }
.kpis { display: flex; flex-wrap: wrap; gap: 12px; }
.tile { border: 1px solid var(--border); border-radius: 8px; padding: 10px 14px;
        min-width: 110px; flex: 1; }
.tile .lab { font-size: 12px; color: var(--ink2); display: flex; align-items: center; gap: 6px; }
.tile .val { margin-top: 4px; }
.tile .num { font-size: 30px; font-weight: 600; }
.tile .sub { font-size: 12px; color: var(--muted); }
.dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; background: var(--muted); }
.d-ok { background: var(--good); } .d-warn { background: var(--warn); } .d-fail { background: var(--fail); }
.chip { display: inline-flex; align-items: center; gap: 6px; padding: 1px 8px;
        border: 1px solid var(--border); border-radius: 999px; font-size: 12px; font-weight: 600; }
.chip.big { font-size: 16px; padding: 3px 12px; }
.c-good .dot { background: var(--good); } .c-warn .dot { background: var(--warn); }
.c-fail .dot { background: var(--fail); } .c-muted .dot { background: var(--muted); }
.why { font-size: 12px; color: var(--ink2); margin-left: 6px; }
.chart { display: flex; align-items: flex-end; gap: 2px; height: 104px;
         border-bottom: 1px solid var(--grid); padding: 4px 0 0; }
.colwrap { position: relative; flex: 1; max-width: 20px; min-width: 6px;
           height: 100%; display: flex; align-items: flex-end; }
.col { display: flex; flex-direction: column; justify-content: flex-end; gap: 2px; width: 100%; }
.seg { width: 100%; }
.seg.cap { border-radius: 4px 4px 0 0; }
.s-ok { background: var(--good); } .s-warn { background: var(--warn); } .s-fail { background: var(--fail); }
.tip { display: none; position: absolute; bottom: calc(100% + 6px); left: 50%;
       transform: translateX(-50%); white-space: nowrap; z-index: 2;
       background: var(--ink); color: var(--page); font-size: 12px;
       padding: 3px 8px; border-radius: 6px; }
.colwrap:hover .tip { display: block; }
.colwrap:hover .seg { filter: brightness(1.12); }
.xlab { display: flex; justify-content: space-between; color: var(--muted);
        font-size: 11px; margin-top: 4px; }
.legend { display: flex; gap: 14px; margin-top: 8px; font-size: 12px; color: var(--ink2); }
.legend > span { display: inline-flex; align-items: center; gap: 6px; }
.tablewrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
th { text-align: left; color: var(--ink2); font-weight: 600; }
th, td { padding: 5px 10px 5px 0; border-bottom: 1px solid var(--grid);
         white-space: nowrap; font-variant-numeric: tabular-nums; }
.notes { color: var(--ink2); font-size: 13px; padding-left: 18px; }
.note { color: var(--muted); font-size: 13px; }
details { margin-top: 12px; }
summary { cursor: pointer; font-size: 13px; color: var(--ink2); }
pre { overflow-x: auto; font-size: 12px; background: var(--page);
      border: 1px solid var(--border); border-radius: 8px; padding: 12px; }
code { font-size: 12px; }
</style>
</head>
<body>
<main>
EOF
  echo "<h1>$(printf '%s' "$COMPANY" | _esc)</h1>"
  echo "<p class=\"gen\">Generated $(date '+%F %T') by <code>orchestrator dashboard</code></p>"

  _section "Company" "$ORCH_HOME/reports"

  # One embedded panel per subsidiary, rendered from the CHILD's own reports.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    repo="${entry%%:*}"; cat="${entry##*:}"
    [ "$cat" = "subsidiary" ] || continue
    _section "Subsidiary — $repo" "$ROOT/$repo/reports"
  done <<< "$(orch_repos)"

  echo "</main>"
  echo "</body>"
  echo "</html>"
} > "$OUT"

echo "dashboard: $OUT"
