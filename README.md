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

See [QUICKSTART.md](QUICKSTART.md) for the full walkthrough and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit.

## Commands

| Command | What it does |
|---|---|
| `orchestrator init [dir]` | Scaffold a company repo (config, roles, skills, org docs) |
| `orchestrator setup` | Onboarding agent: interviews you and configures the whole company |
| `orchestrator health [--local]` | The scorecard: gates, hygiene, motion, backlog → GREEN/YELLOW/RED |
| `orchestrator standup [days]` | What moved across the company + open PRs |
| `orchestrator sync [--install\|--check]` | Live skills ⇄ committed copy |
| `orchestrator hire [--dry-run]` | Autonomous hiring round: hire/fire/update the roster |
| `orchestrator propose [--dry-run]` | Research + propose the next repo (strategy) |
| `orchestrator sweep` | The daily health + standup, committed |
| `orchestrator doctor` | Check dependencies and config |
| `orchestrator hook` | Print the PostToolUse hook + cron to wire up |

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

## License

Proprietary. See [LICENSE](LICENSE). Not open source — this is a commercial
product.
