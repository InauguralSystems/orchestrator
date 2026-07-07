# ROSTER — who works here

Every employee is a skill in `~/.claude/skills/` (committed copy in this
repo's `skills/`). "Invoke" means route the task through that skill. Full job
descriptions live in `roles/`. Hiring = writing a skill. Firing = deleting one.

## Org chart

<!-- ADAPT: mirror your real roster. Each leaf is a skill name. -->
```
CEO (<your name>)
└── Chief of Staff ......... triage
    ├── Ops Manager ....... workflow (operating rhythm)
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
