---
name: workflow
description: The operating rhythm. Use as the company handbook for how any change moves from request to landed-and-green in any repo — adversarial review before merge, the per-repo validation gates, commit/push/CI cadence, background-work handling, and honest reporting. Every specialist follows this loop; triage names the owner, this governs how they work.
---

# Workflow — the operating rhythm

How a change moves from request to landed-and-green in any repo of the
company. Every employee follows this loop; it is the company's Ops Manager.

## The loop
1. **Understand** the task and its acceptance criteria before touching code.
2. **Smallest artifact** that moves it — a merged change beats a plan.
3. **Adversarial review** before merge: try to break your own change; assume
   the first version is wrong until a gate says otherwise.
4. **Gates** (per repo — define yours below): build passes, tests pass,
   lints clean. A turn does not end on a broken build.
5. **Land**: commit with a clear message, push, watch CI to green.
6. **Report honestly**: failed tests reported with their output; skipped
   steps named as skipped; "done" only after it's verified.

## Gates (per repo)
<!-- ADAPT: list each repo's mechanical pass/fail bar. Example:
     - web:   `npm test && npm run lint && npm run build`
     - core:  `make check` (unit + integration, 0 warnings)
     A gate is a command with a pass/fail exit code, not a vibe. -->
- `<repo>`: `<the command that must pass>`

## Honest reporting
- A broken build is a failed deliverable, not a status update.
- A perf claim needs a repeatable measurement, not an assertion.
- A revert of a bad change beats limping it past the gate.

## Background & long-running work
- Kick long jobs off explicitly and say what is running; report a job's
  result only once it has finished and you have observed it.
