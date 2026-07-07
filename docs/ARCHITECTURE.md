# Architecture

Orchestrator is a thin, dependency-light layer over Claude Code skills and git.
The design goal is that **nothing about your company is hardcoded** — every
org-specific fact lives in one config file, and the tooling is generic.

## The product / company split

There are two things, and keeping them separate is the whole idea:

- **The product** (this repo): the CLI, the tools, the templates. Installed
  once, on PATH. You never edit it per-company.
- **A company** (a repo *you* own): an `orchestrator.yaml`, a `skills/`
  directory (your committed employees), `roles/`, the org docs, and `reports/`.
  You can run many companies off one product install; each is just a config.

The CLI locates the active company by finding `orchestrator.yaml` (via
`$ORCH_CONFIG`, then `./`, then `$ORCH_HOME`). `lib/config.sh` resolves it and
sets `ORCH_HOME` to the company dir; every tool sources that.

```
orchestrator (CLI)  ──sources──▶  lib/config.sh  ──reads──▶  orchestrator.yaml
      │                                                          (the company)
      ├─ init      scaffold a company from templates/
      ├─ health    tools/health.sh    ─┐
      ├─ standup   tools/standup.sh    ├─ read-only: git + gh, write reports/
      ├─ sweep     tools/daily_sweep.sh┘
      ├─ sync      tools/sync_skills.sh   live skills ⇄ committed copy
      ├─ hook      prints PostToolUse + cron wiring
      └─ doctor    deps + config check
```

## The config

`orchestrator.yaml` is parsed in pure awk/bash (no `yq`/python dependency),
supporting a small flat schema: scalars (`company`, `ceo`, `github_org`,
`root`, `live_skills`, `skills_dir`) and two lists (`repos:` as
`- name:category`, `vetoes:`). `lib/config.sh` exposes `orch_get`,
`orch_repos`, `orch_vetoes`, and `orch_expand`.

## The metaphor, made mechanical

| Company concept | Implementation |
|---|---|
| Employee | a skill in `~/.claude/skills/` |
| Job description | a charter in `roles/` |
| Org chart | `ROSTER.md` + the `repos:` config |
| Constitution | `vetoes:` in `orchestrator.yaml` |
| Chief of Staff | the `triage` skill (routes every task) |
| Ops Manager | the `workflow` skill (the per-change loop) |
| HR / hiring | the `hiring-manager` skill + `orchestrator hire` |
| Performance review | `orchestrator health` |
| "Nobody has to remember" | the daily-sweep cron + the sync hook |

## The hiring engine

Deciding who to hire needs the model, so it is not a shell script — it is the
`hiring-manager` skill, launched by `orchestrator hire`. The CLI is a thin
launcher: it reads `repos:` and the current roster from config, builds a round
prompt, and runs it through the local `claude` CLI (paste-the-prompt fallback
if `claude` is absent). The skill does the multi-agent work — a recruiter
subagent per repo (fan-out), a committee dedup (barrier), then author +
adversarial verify per candidate. Hiring writes a new `SKILL.md`; firing
deletes one (fully autonomous — git and the ROSTER hiring log are the audit
trail); updating edits a charter in place. Whatever it touches, the PostToolUse
sync hook mirrors and commits — so the decision engine and the bookkeeping stay
decoupled: `hire` decides, the hook records. `ORCH_CLAUDE_FLAGS` (e.g.
`--permission-mode acceptEdits`) controls how hands-off a round runs.

## Health signals

Read-only, from git + the GitHub API. Never builds, tests, or mutates a repo.
Per repo: **CI gate** (red default branch = company FAIL), **hygiene** (clean
tree, in sync with origin), **motion** (commits in 7d/30d; parked repos exempt,
siblings exempt from motion), **backlog** (open issues+PRs). Plus a
company-wide **skills-drift** check. Scored `FAIL > WARN > OK` into
GREEN/YELLOW/RED, appended to `reports/history.csv` as a trend.

Pin/freshness checks (does consumer X track product Y's release?) are
release-model-specific and intentionally *not* generalized in v1 — they're a
documented extension point in `tools/health.sh` and `METRICS.md`.

## What generalization removed

The system this came from had one org, one product (a programming language),
and twenty named repos welded into every script. Generalizing meant: lifting
all of that into `orchestrator.yaml`, replacing the language-specific
pin-freshness signal with a documented seam, turning the one org's roster into
editable templates, and making every path config-derived so there's not a
single `/home/<someone>` or org name left in the code.
