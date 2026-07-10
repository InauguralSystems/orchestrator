# Orchestrator

**Run your solo dev shop like a company — as code.**

Orchestrator turns a folder of Claude Code skills into a staffed company. A
**skill** is a hired employee. A **role charter** is their job description. A
**config file** is your org chart. `orchestrator health` is the performance
review. Hiring is writing a skill; firing is deleting one.

It is the generalized, product form of a private company-orchestration system
that ran a real multi-repo portfolio: the machinery — the triage → owner →
workflow loop, the read-only health scorecard, the auto-syncing skill roster,
the daily sweep — with none of the specifics welded in. You point it at *your*
repos and it runs *your* company.

## Why

A solo founder with AI employees still needs the boring parts of a company:
someone to route work, someone to enforce the operating rhythm, and
instruments that measure health so nobody has to *remember* to check. Vibes
don't scale to twenty repos. Orchestrator makes the org legible:

- **One front door.** Every task goes through a Chief-of-Staff `triage` skill
  that names exactly one owner and the smallest useful next action — never a
  menu of options.
- **A measured company, not a claimed one.** `orchestrator health` reads git
  and the GitHub API (never builds or mutates) and scores every repo on
  gates, hygiene, motion, and backlog. It writes a trend, not a snapshot, and
  exits non-zero on RED so it can gate your automation.
- **A roster that hires itself.** `orchestrator hire` runs an autonomous
  hiring round: a recruiter agent per repo finds recurring work with no owner,
  a committee dedups across them, each candidate is authored and adversarially
  verified, skills whose work is gone are fired, and the round is logged — all
  without you hand-writing a file. Zero-hire is the default; headcount is
  attention-cost. A PostToolUse hook then mirrors and commits the result, so
  the committed roster stays in lockstep with the live one, mechanically.
- **A daily sweep.** A cron job runs health + standup, commits the reports,
  and shouts on RED — the backlog gets checked even when nobody asks.
- **Security, pre-hired.** Every company ships with a `security` employee — an
  AppSec reviewer for secrets, injection, auth boundaries, SSRF, and
  supply-chain risk — because the people who most need it are the ones who
  forget to add it.

## Install

```sh
git clone <your-fork>/orchestrator.git ~/tools/orchestrator
ln -s ~/tools/orchestrator/orchestrator ~/.local/bin/orchestrator   # on PATH
orchestrator doctor
```

Requires `git`, `awk`, `sed`, `jq`. `rsync` and `gh` (GitHub CLI) are optional:
`rsync` speeds up skill sync (falls back to `cp`), `gh` unlocks the CI and
backlog signals.

## Quickstart

```sh
cd ~/src/mycompany            # a repo that will BE your company layer
orchestrator init             # scaffolds config + roster + org docs
orchestrator sync --install   # make the starter skills live
orchestrator setup            # the onboarding agent configures everything:
                              # interviews you, writes the config, adapts the
                              # templates, wires the hooks, runs the first
                              # hiring round, and verifies the company is green
```

Prefer to do it by hand? `orchestrator init` then edit `orchestrator.yaml`,
`orchestrator doctor`, `orchestrator hook`, `orchestrator hire`,
`orchestrator health --local`.

See [QUICKSTART.md](QUICKSTART.md) for the full walkthrough,
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit, and
[docs/DESIGN.md](docs/DESIGN.md) for *why* they fit that way — the design
rationale (proof over belief, recovery over accuracy, the gate/hook/flywheel
stack, and the economics of running it on any model).

## Commands

| Command | What it does |
|---|---|
| `orchestrator init [dir]` | Scaffold a company repo (config, roles, skills, org docs) |
| `orchestrator setup` | Onboarding agent: interviews you and configures the whole company |
| `orchestrator health [--local]` | The scorecard: gates, hygiene, motion, backlog → GREEN/YELLOW/RED |
| `orchestrator standup [days]` | What moved across the company + open PRs |
| `orchestrator dashboard` | Render `reports/` into one self-contained HTML dashboard (health trend, repo table, standup, embedded subsidiary panels) |
| `orchestrator sync [--install\|--check]` | Live skills ⇄ committed copy |
| `orchestrator hire [--dry-run]` | Autonomous hiring round: hire/fire/update the roster |
| `orchestrator propose [--dry-run]` | Research + propose the next repo (strategy) |
| `orchestrator work [--dry-run]` | **The on-button.** Start an autonomous work session: report to the Chief of Staff, work the backlog, escalate to `propose` when it's dry, halt honestly when there's nothing real left |
| `orchestrator progress [note]` | The work loop's external memory: no arg prints the progress file; a note appends a timestamped entry, so a later session resumes without re-deriving |
| `orchestrator sweep` | The daily health + standup + dashboard, committed |
| `orchestrator doctor` | Check dependencies and config |
| `orchestrator hook` | Print the PostToolUse hook + cron to wire up |

## The work loop (the on-button)

`orchestrator work` is the front door to the whole system. One command builds a
kickoff from your config and hands it to Claude: *report to the Chief of Staff,
work autonomously until told to stop or wrap.* It runs on **your** Claude Code
account (it `exec`s the `claude` CLI — no API keys, nothing hosted), local, with
your gates enforcing every change.

The loop is designed to keep going **only while there's real value**, and to stop
honestly when there isn't:

```
report to the Chief of Staff → route work → owner does it (gates + adversarial review)
  ↳ backlog dry?  → propose: research, surface gaps, adversarially review them
        ↳ real gap?      → route it, keep going
        ↳ genuinely dry? → WRAP: report what was done, stop (never manufacture work)
  hits a decision? → research the best approach first
        ↳ how / reversible / within vetoes?              → decide, proceed
        ↳ whether / irreversible / outward-facing / spend? → escalate, pre-researched, one rec
```

Two properties make it trustworthy rather than a runaway: it **halts honestly**
(zero-proposals is a valid outcome — it won't invent work to stay busy), and it
**escalates only what's irreducibly the CEO's** (research resolves *how*
questions; *whether* questions still come to you). For a hands-off session,
`export ORCH_CLAUDE_FLAGS="--permission-mode acceptEdits"` first. `--dry-run`
prints the exact prompt without running it.

## Safe autonomy (the guardrail pack)

The loop above only runs unattended because of the layer beneath it: **hooks —
deterministic code the model cannot talk past.** Guidelines live in prompts and
are advisory; guardrails live in hooks and are enforced. `orchestrator hook`
installs three:

| Hook | Event | What it mechanically enforces |
|---|---|---|
| `deny_guard.sh` | PreToolUse[Bash] | Denies the irreversible: force-push/delete of a `protected_branches`, `rm -r` of a home/root path. Low false-positive (feature-branch force-push, subpath `rm`, and normal push are allowed; heredocs are exempt). |
| `stop_gate.sh` | Stop | A turn can't end with a red `gate:` on a dirty tree — the loop keeps fixing instead of stopping on red. Clean tree = instant no-op. |
| `hook_skill_sync.sh` | PostToolUse[Write] | The committed roster stays == the live one. |

The design rule: **what must hold goes in a hook, not a prompt.** Each guard is
minimal and incident-shaped (guardrails cost false positives — add one when
something actually went wrong), has an escape hatch (`stop_gate` consumes its
skip flag per-stop so you can't leave it off), and lives outside the loop's reach
(the deny-guard exempts content-writing so it can't be patched-past via Bash).
They are defense in depth, not a security boundary.

**The interlock:** `orchestrator work --permission-mode acceptEdits` **refuses to
run** unless `deny_guard` + `stop_gate` are installed — no unsupervised autonomy
without the floor beneath it (`ORCH_UNSAFE=1` overrides, explicitly).

## Verifying perf claims — the n=5 gate

A build/test gate is **binary** (red or green) — the right check for *correctness*,
and what the Stop-gate enforces. A **performance** claim is not binary: one run is
noise. So the product has a second gate tier — `orchestrator perf-gate` — that
makes "n=5 for any perf claim" mechanical instead of a rule you have to remember:

```sh
orchestrator perf-gate baseline   # run the bench n=5, record the baseline
# ... make the change ...
orchestrator perf-gate check      # run n=5; PASS only on a confirmed, non-overlapping speedup
```

It runs `perf_gate:` (a command that prints one metric number) N times, takes the
median + full spread, and **rejects a "win" whose n=5 distribution overlaps the
baseline's** — if the ranges overlap, the difference isn't real yet. It fails a
regression and refuses a check with no baseline. `--no-regress` proves only
absence of a regression (for perf-neutral changes). Theory is great; this is the
reality check — the agent doesn't get to *believe* it's faster, it has to
*measure* it, which is exactly the ground-truth verification that keeps an
autonomous loop honest.

## Autonomous hiring

The roster runs itself. `orchestrator hire` builds a round prompt from your
config and hands it to the `hiring-manager` skill (your HR employee), which:

1. **Recruits** — one subagent per active repo finds recurring work with no
   current owner (default answer: zero-hire).
2. **Committee** — dedups proposals across repos into candidate roles.
3. **Authors + verifies** — drafts each `SKILL.md` and adversarially checks the
   hire is worth the headcount; a scope note on an existing skill beats a new one.
4. **Fires** — deletes skills whose work is gone (fully autonomous; git + the
   ROSTER hiring log are the audit trail).
5. **Logs** — records the round in `ROSTER.md` and reconciles the triage roster.

It runs through your local `claude` CLI. For a hands-off round, export the
autonomy flag first:

```sh
export ORCH_CLAUDE_FLAGS="--permission-mode acceptEdits"
orchestrator hire            # or: orchestrator hire --dry-run  to see the prompt
```

If `claude` isn't installed, `hire` prints the round prompt to paste into a
Claude Code session.

To keep the roster current without asking, `orchestrator hook` prints a
ready-made **weekly** cron line (Mondays 09:00) that runs `tools/hiring_round.sh`
headless with the autonomy flag set. A round is expensive — a recruiter agent
per repo — so it runs on its own weekly cadence, separate from the daily sweep.

## Strategy: proposing the next repo

`orchestrator propose` is to *projects* what `hire` is to *people*. It launches
the `portfolio-strategist` skill, which:

1. **Refreshes `PORTFOLIO.md`** — the coverage map of what each repo exercises
   vs. which areas nothing covers yet.
2. **Ranks the uncovered lanes** by how much of the core they'd exercise,
   whether a credible external yardstick exists, and what else they'd force.
3. **Researches the top candidate** through the `deep-research` skill — prior
   art, reference implementations, test corpora — delivered with citations.
4. **Writes at most one proposal** under a house contract: the gap it fills,
   how success is validated (externally, not self-graded), the findings ledger,
   and a smallest-first milestone. **Zero proposals is a valid outcome** — it
   won't manufacture a project to look busy.

The proposal goes to you (the CEO) for the go/no-go; the builder executes it.
Wire it to a monthly cron the same way as the hiring round.

## Testing

A self-contained regression suite ships in [`tests/`](tests/) — TAP output,
**no dependency beyond what the product already needs** (no `bats` to install):

```sh
bash tests/run.sh        # 64 checks across every subcommand; exit 0 iff green
```

It covers scaffolding, the config parser, health scoring + reports, the
live⇄repo sync with its firing (delete) semantics + the destructive-target
guard, the auto-commit hook, the agentic launchers, and `bash -n` on every
script. See [tests/README.md](tests/README.md). CI
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the suite +
`bash -n` + advisory `shellcheck` on every push.

## Security

Every company ships with a `security` employee, and the product holds its own
code to the same bar. Trust model, hardening notes, and disclosure policy are
in [SECURITY.md](SECURITY.md). In short: run it against repos you own, keep the
company repo private (the hook and sweep auto-push), and only run autonomous
`hire`/`propose` rounds over trusted repos.

## License

Proprietary. See [LICENSE](LICENSE). Not open source — this is a commercial
product.
