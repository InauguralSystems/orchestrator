# ROSTER — who works here

Every employee is a skill in `~/.claude/skills/` (committed copy in this
repo's `skills/`). "Invoke" means route the task through that skill. Full job
descriptions live in `roles/`. Hiring = writing a skill. Firing = deleting one.

## Org chart

<!-- ADAPT: mirror your real roster. Each leaf is a skill name. -->
```
CEO (<your name>)
└── Chief of Staff ......... triage
    ├── Onboarding ........ company-setup (day-zero; dormant after)
    ├── Ops Manager ....... workflow (operating rhythm)
    ├── HR ................ hiring-manager (runs the hiring rounds)
    ├── Strategy .......... portfolio-strategist (research + next-repo proposals)
    ├── Core dept
    │   └── Core Engineer . <your-core-engineer-skill>
    ├── Frontend dept
    │   └── Frontend Eng .. <your-frontend-skill>
    ├── Platform dept
    │   └── Release Eng ... <your-release-skill>
    ├── Security dept
    │   └── AppSec Eng .... <your-security-skill>
    └── DX dept
        └── Docs/DX Eng ... <your-docs-skill>
```

## Standing vetoes (the constitution)

Settled decisions. Employees do not re-open them; the Chief of Staff rejects
work that violates them. The source of truth is `orchestrator.yaml`:

<!-- ADAPT: paste your vetoes here, or regenerate from orchestrator.yaml. -->
1. <veto one>
2. <veto two>

## Handbooks vs. employees

Some skills are not employees but shared training every employee follows —
e.g. `workflow`. List yours here so it's clear which skills route work and
which are company-wide method.

## Hiring history

`orchestrator hire` appends a dated entry here every round — repos surveyed,
hires (with why), zero-hire verdicts (a zero is a decision worth recording),
fires, and charter updates. This is the audit trail for an autonomous roster.

<!-- Example shape (the hiring-manager fills these in):
**2026-01-15 hiring round** (survey of N repos): 1 hire — <role> (owns <work>).
Zero-hire verdicts: <repos> — existing charters already cover their work.
Fires: <skill> (its repo was parked). -->

