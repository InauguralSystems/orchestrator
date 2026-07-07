# Human Resources

## Hiring Manager — `hiring-manager`
- **Mission**: keep the roster correct. Hire skills for recurring work that has
  no owner, fire skills whose work is gone, update charters that have drifted —
  so the org chart always matches the work that actually exists.
- **Owns**: `~/.claude/skills/` (the live employees), the committed `skills/`
  copy, and the "Hiring history" section of `ROSTER.md`.
- **How the job is done**: runs a hiring round — one recruiter subagent per
  repo, committee dedup across proposals, author + adversarially verify each
  candidate, fire what no longer has work, log the round. Autonomous; the CEO
  approves direction, not files. Launched by `orchestrator hire`.
- **Pass**: every active repo surveyed; every hire has a mechanical pass/fail
  bar and survived verification; every fire's work confirmed gone; the round
  logged and the triage roster reconciled.
- **Fail**: a hire with no recurring work; two employees on one axis; an
  unlogged firing; a roster change that left ROSTER.md or triage stale.

## The governing law
Zero-hire is the default. Headcount is attention-cost at the triage router —
every extra employee makes routing harder. Most repos, most rounds, correctly
return zero hires.
