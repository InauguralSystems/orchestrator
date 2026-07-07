# METRICS — how company health is measured

Principle: **measurement is the moat**. Health is what the instruments say,
never what a summary claims. `orchestrator health` is read-only (git + GitHub
API); it never builds, tests, or mutates a repo.

## The signals

### 1. Gates (weight: highest)
Latest CI conclusion per repo (`gh run list -L1`). A red default branch is a
company-level FAIL — nothing outranks it. Repos without workflows report `-`.

### 2. Hygiene
Per repo: working tree clean, and local HEAD neither ahead of nor behind
`origin`. Dirty or ahead/behind → WARN (normal mid-session, bad at end of day).

### 3. Motion
Commits in the last 7 and 30 days. An **active** repo with 0 commits in 30
days → WARN (drifting). **Parked** repos are expected to be silent — motion
there is the anomaly worth noticing, not the silence. **Sibling** repos are
exempt (their cadence couples to a checkout, not their own history).

### 4. Skills drift
The committed employee copy (`skills/`) must match the live tree
(`~/.claude/skills/`). Any drift → one company-level WARN; `orchestrator sync`
resolves it (the live tree wins on the dev box).

### 5. Backlog pressure
Open issues+PRs per repo. No absolute threshold — tracked in history so
*pileup trends* are visible.

## Scoring

Each active repo gets the worst status among its signals: `FAIL > WARN > OK`.

| Company state | Meaning |
|---|---|
| **GREEN** | 0 FAIL, ≤2 WARN |
| **YELLOW** | 0 FAIL, >2 WARN |
| **RED** | any FAIL |

`orchestrator health` exits 1 on RED so it can gate automation.

## Trend, not snapshot

Every run appends to `reports/history.csv`: `date, ok, warn, fail, state`.
Reviewing the company = reading `reports/latest.md` and diffing history.

## Extending the signals

Freshness/pin checks (does consumer X track product Y's latest release?) are
release-model-specific and left as a per-company extension: add the check in
`tools/health.sh` where the category loop runs, and document it here.
