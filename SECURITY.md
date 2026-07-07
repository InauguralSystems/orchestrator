# Security

Orchestrator ships with a `security` employee pre-hired in every company, and
holds its own code to the same bar. This file is the disclosure policy and the
trust model.

## Reporting a vulnerability

Email the maintainer (the address in the commercial license) with a
repro-grounded description. Please don't open public issues for undisclosed
vulnerabilities.

## Trust model

Orchestrator is a **private company layer**: a CLI plus shell tools that run on
a developer's own machine against repos they own. It has no server and no
network listener. Its sensitive operations are local file mirroring and
`git push`. Design accordingly:

- **Run it against repos you own.** The health/standup instruments are
  read-only, but the autonomous rounds are not (below).
- **Keep the company repo private.** The sync hook and daily sweep
  auto-`git push`; anything committed to `skills/` or `reports/` is published
  immediately. Never put secrets in a skill or a report — use a private remote.

## Hardening notes (from the self-review)

- **Destructive mirror is guarded (fixed).** `sync --push` performs a
  delete-mirror of the live skills into the committed copy. A `skills_dir`
  misconfiguration (`.`, `..`, `~`, `/`) previously could have turned that into
  an `rm -rf` of the repo root or `$HOME`. `tools/sync_skills.sh` now refuses a
  destructive mirror into any target that isn't strictly inside the company
  repo; regression test in `tests/test_sync.sh`.
- **Autonomous rounds and untrusted content (operational).** `orchestrator
  hire` / `propose` on the weekly cron run with
  `ORCH_CLAUDE_FLAGS="--permission-mode acceptEdits"`; recruiter/strategist
  agents read repo files, and a round can write/delete skill files and push.
  Content in a repo you don't fully control is a prompt-injection surface.
  **Only run autonomous rounds over repos you own.** For a repo whose contents
  you don't trust, run the round interactively (drop `acceptEdits`) and review
  the diff before it lands.
- **`ORCH_CLAUDE_FLAGS` is your autonomy dial.** Leave it unset for
  interactive, human-in-the-loop rounds; set it only for cron cadence on
  trusted repos.

## Reviewing your own company

Route any security-sensitive change through the `security` skill, and run a
review before a release. The skill optimizes for reachable, repo-grounded
findings — not exploit drama — and ships each fix with a before/after test.
