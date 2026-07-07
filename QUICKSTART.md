# Quickstart

From zero to a measured company in about ten minutes.

## 0. Prerequisites

- [Claude Code](https://claude.com/claude-code) with skills in `~/.claude/skills/`
- `git`, `awk`, `sed`, `jq` on PATH (`orchestrator doctor` checks)
- Optional: `rsync` (faster skill sync; falls back to `cp`), and `gh`
  (GitHub CLI), authenticated — enables the CI + backlog signals
- A parent directory that holds all your repos, e.g. `~/src/mycompany/`

## 1. Install the product

```sh
git clone <your-fork>/orchestrator.git ~/tools/orchestrator
ln -s ~/tools/orchestrator/orchestrator ~/.local/bin/orchestrator
orchestrator version
```

## 2. Create your company layer

Pick (or make) a repo that will *be* your company layer — the equivalent of a
"headquarters" repo that sits alongside your product repos.

```sh
cd ~/src/mycompany/hq
git init
orchestrator init
```

This scaffolds:

```
orchestrator.yaml          your company as config — edit this first
roles/                     job charters (executive-ops + a specialist template)
skills/triage/             starter Chief-of-Staff skill
skills/workflow/           starter operating-rhythm skill
ROSTER.md METRICS.md PORTFOLIO.md   org docs
reports/                   health history lands here
```

## 3. Fill in the config

Edit `orchestrator.yaml`: your `company` name, the `ceo`, your `github_org`,
the `root` dir that holds your repos, the `repos:` list (with a category each),
and your standing `vetoes:`. See `orchestrator.example.yaml` for every field.

```sh
orchestrator doctor        # confirms deps + that your config parses
```

## 4. Hire your first employees

The `triage` and `workflow` skills ship as adaptable templates. Edit their
`SKILL.md` files to name your real roster, then add specialist skills (one per
discipline) to `~/.claude/skills/`. Each new skill is a new hire.

## 5. Wire up the machinery

```sh
orchestrator hook          # prints the PostToolUse hook + the cron line
```

Paste the hook block into `~/.claude/settings.json` and add the cron line to
`crontab -e`. Now:

- editing any `~/.claude/skills/...` file auto-mirrors + commits it here, and
- a daily sweep runs health + standup, commits the reports, and shouts on RED.

## 6. Run the company

```sh
orchestrator health --local   # your first scorecard (no network)
orchestrator health           # full scorecard with CI + backlog (needs gh)
orchestrator standup 7        # what moved in the last week
orchestrator sync --check     # confirm live skills == committed copy
```

`reports/latest.md` is the current scorecard; `reports/history.csv` is the
trend. Reviewing the company is reading those two files.
