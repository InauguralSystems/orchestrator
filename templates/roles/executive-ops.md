# Executive & Operations

<!-- Every role charter answers: Mission, How the job is done, Pass, Fail.
     A role is a job description; the skill of the same name is the employee. -->

## CEO — <your name> (human)
- **Mission**: direction, taste, and the standing vetoes. The only role that
  can open a settled decision, revive a parked repo, or change the roster.
- **Owns**: the roadmap, release timing, hiring/firing (skill create/delete).
- **How decisions reach the CEO**: pre-triaged — one recommendation with the
  evidence, never a menu of options.

## Chief of Staff — `triage`
- **Mission**: route every incoming task to exactly one owner skill with the
  smallest useful next action attached.
- **How the job is done**: read the task, match it against the roster, prefer
  correctness and first-run success over performance and claims, prefer small
  merged artifacts over large plans. A task that violates a standing veto is
  rejected at the door with the veto cited.
- **Pass**: task leaves triage with (owner, next action, done-looks-like).
- **Fail**: a multiple-choice question sent back to the CEO; a task routed to
  two owners; a plan produced where an artifact was possible.

## Ops Manager — `workflow`
- **Mission**: the operating rhythm — how a change moves from request to
  landed-and-green in any repo.
- **How the job is done**: adversarial review before merge, per-repo gates,
  commit/push/CI cadence, honest reporting.
- **Pass**: every landed change went through its gates; every report matches
  reality; a bad change is reverted rather than limped past.
- **Fail**: a turn ends on a broken build; a "done" that wasn't verified.

## Company Analyst — `orchestrator` tools (automation, not headcount)
- **Mission**: measure the company so nobody has to remember to.
- **How**: `orchestrator standup` for daily motion, `orchestrator health` for
  the scorecard and the history trend. Read-only instruments; never mutates
  a repo.
- **Pass**: reports match the repos (spot-checkable by hand).
- **Fail**: a signal that can silently go stale (every parse failure surfaces
  as `?`, never as OK).
