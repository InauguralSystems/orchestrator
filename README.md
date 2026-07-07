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
- **A roster that can't drift.** A PostToolUse hook mirrors your live skills
  into the repo and commits them the moment you edit one — the committed
  employee roster stays in lockstep with the live one, mechanically.
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
cd ~/src/mycompany          # a repo that will BE your company layer
orchestrator init           # scaffolds config + roster + org docs
$EDITOR orchestrator.yaml   # your company, repos, and vetoes
orchestrator doctor         # verify deps + config
orchestrator hook           # print the auto-sync hook + cron to install
orchestrator health --local # your first scorecard
```

See [QUICKSTART.md](QUICKSTART.md) for the full walkthrough and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit.

## Commands

| Command | What it does |
|---|---|
| `orchestrator init [dir]` | Scaffold a company repo (config, roles, skills, org docs) |
| `orchestrator health [--local]` | The scorecard: gates, hygiene, motion, backlog → GREEN/YELLOW/RED |
| `orchestrator standup [days]` | What moved across the company + open PRs |
| `orchestrator sync [--install\|--check]` | Live skills ⇄ committed copy |
| `orchestrator sweep` | The daily health + standup, committed |
| `orchestrator doctor` | Check dependencies and config |
| `orchestrator hook` | Print the PostToolUse hook + cron to wire up |

## License

Proprietary. See [LICENSE](LICENSE). Not open source — this is a commercial
product.
