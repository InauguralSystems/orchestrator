# tests — the Orchestrator regression suite

A self-contained TAP suite with **no dependency beyond what the product itself
needs** (git/awk/sed/jq/bash). The standing "zero new dependencies" veto
applies to the tests too, so buyers and CI can run them anywhere the product
runs — no `bats` install required.

```sh
bash tests/run.sh        # runs everything; exit 0 iff all green
```

## Layout

- `run.sh` — the runner. Sources `lib.sh` + every `test_*.sh`, runs each `t_*`
  function against throwaway fixture companies, prints TAP, exits nonzero on
  any failure.
- `lib.sh` — TAP assertions (`assert_eq`, `assert_contains`, `assert_file`,
  `assert_ok`, `assert_fail`) and fixtures (`mkcompany`, `mkrepo`, `mkempty`).
- `test_cli.sh` — version/help/unknown-command + `bash -n` on every script
  (the `orchestrator-cli-engineer` mechanical bar).
- `test_init.sh` — scaffolding + the no-clobber guard.
- `test_config.sh` — the pure awk/bash config loader.
- `test_health.sh` — scoring, the report/trend artifacts, exit codes.
- `test_sync.sh` — live⇄repo mirror + delete (firing) semantics.
- `test_hook.sh` — auto-commit on a skill edit, no-op otherwise.
- `test_agentic.sh` — the `setup`/`hire`/`propose` launchers build correct
  prompts (`--dry-run`, so no `claude` is invoked).

## Adding a test

Drop a `t_yourcase` function into the matching `test_*.sh` (or a new one). The
runner discovers it automatically. Bugs the suite finds go in `FINDINGS.md`.
