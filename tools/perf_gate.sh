#!/usr/bin/env bash
# perf_gate.sh — the n=5 statistical gate. Turns "n=5 for any perf claim" from a
# prose rule into a mechanical one. Unlike a build/test gate (binary pass/fail),
# a perf claim is statistical: it runs the benchmark N times (default 5), takes
# the median + full spread, and refuses a "win" whose distribution OVERLAPS the
# baseline's — if the ranges overlap, the difference isn't real yet. Theory is
# great; this is the reality check the model can't talk past.
#
# Usage:
#   perf_gate.sh baseline            record the current bench as the baseline (n runs)
#   perf_gate.sh check               PASS only on a CONFIRMED (non-overlapping) speedup
#   perf_gate.sh check --no-regress  PASS unless a confirmed regression (perf-neutral changes)
#
# Config (orchestrator.yaml):
#   perf_gate: <cmd that prints one metric number per run>   (required; else no-op)
#   perf_n: <runs, default 5, min 3>
#   perf_lower_is_better: <true|false, default true>
set -u
PRODUCT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$PRODUCT/lib/config.sh" || exit 1

BENCH="$(orch_get perf_gate 2>/dev/null || true)"
[ -n "${BENCH:-}" ] || { echo "perf_gate: no 'perf_gate:' command configured — nothing to measure." >&2; exit 0; }
N="$(orch_get perf_n 5)"; case "$N" in ''|*[!0-9]*) N=5;; esac; [ "$N" -ge 3 ] 2>/dev/null || N=5
LOWER="$(orch_get perf_lower_is_better true)"
BASE="$ORCH_HOME/reports/.perf_baseline"
mode="${1:-check}"; opt="${2:-}"
cd "$ORCH_HOME" || exit 1
mkdir -p reports

# samples — run the bench N times, echo the last numeric token from each run.
samples() {
  local i out num
  for ((i=1; i<=N; i++)); do
    out="$(eval "$BENCH" 2>/dev/null)" || { echo "perf_gate: bench command failed on run $i" >&2; return 1; }
    num="$(printf '%s' "$out" | grep -oE '[0-9]+([.][0-9]+)?' | tail -1)"
    [ -n "$num" ] || { echo "perf_gate: bench produced no numeric metric on run $i" >&2; return 1; }
    echo "$num"
  done
}

case "$mode" in
  baseline)
    s="$(samples)" || exit 1
    printf '%s\n' "$s" > "$BASE"
    echo "perf_gate: baseline recorded (n=$N): $(printf '%s' "$s" | tr '\n' ' ')"
    exit 0 ;;
  check)
    [ -f "$BASE" ] || { echo "perf_gate: no baseline — run 'perf-gate baseline' BEFORE the change." >&2; exit 1; }
    cur="$(samples)" || exit 1
    curf="$(mktemp)"; printf '%s\n' "$cur" > "$curf"
    awk -v lower="$LOWER" -v norg="$opt" '
      function median(a, n,   i,j,t) {
        for (i=2;i<=n;i++){ t=a[i]; j=i-1; while (j>=1 && a[j]>t){ a[j+1]=a[j]; j-- } a[j+1]=t }
        return (n%2) ? a[(n+1)/2] : (a[n/2]+a[n/2+1])/2
      }
      FNR==NR { b[++nb]=$1; if(nb==1||$1<bmin)bmin=$1; if(nb==1||$1>bmax)bmax=$1; next }
              { c[++nc]=$1; if(nc==1||$1<cmin)cmin=$1; if(nc==1||$1>cmax)cmax=$1 }
      END {
        bmed=median(b,nb); cmed=median(c,nc); low=(lower!="false")
        if (low) { win=(cmax<bmin); reg=(cmin>bmax) } else { win=(cmin>bmax); reg=(cmax<bmin) }
        printf "perf_gate: baseline n=%d  median=%.4g  [%.4g..%.4g]\n", nb, bmed, bmin, bmax
        printf "perf_gate: current  n=%d  median=%.4g  [%.4g..%.4g]\n", nc, cmed, cmin, cmax
        if (reg) { print "perf_gate: FAIL — confirmed REGRESSION (n=5 distributions separated the wrong way)."; exit 1 }
        if (norg=="--no-regress") { print "perf_gate: PASS — no regression (overlap or improvement is acceptable)."; exit 0 }
        if (win) { print "perf_gate: PASS — confirmed speedup (non-overlapping n=5 distributions)."; exit 0 }
        print "perf_gate: FAIL — n=5 distributions OVERLAP; the difference is not real yet (need a bigger effect or more runs)."; exit 1
      }' "$BASE" "$curf"
    rc=$?; rm -f "$curf"; exit $rc ;;
  *) echo "usage: perf_gate.sh [baseline | check [--no-regress]]" >&2; exit 2 ;;
esac
