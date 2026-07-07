#!/usr/bin/env bash
# init: scaffolds a company, and refuses to clobber an existing one.

t_init_scaffolds_files() {
  local co; co="$(mkempty)"
  runco "$co" init >/dev/null 2>&1
  assert_file "init writes orchestrator.yaml" "$co/orchestrator.yaml"
  assert_file "init makes roles/"             "$co/roles"
  assert_file "init makes skills/"            "$co/skills"
  assert_file "init makes reports/"           "$co/reports"
  assert_file "init writes ROSTER.md"         "$co/ROSTER.md"
  assert_file "init writes METRICS.md"        "$co/METRICS.md"
  assert_file "init writes PORTFOLIO.md"      "$co/PORTFOLIO.md"
}

t_init_scaffolds_starter_skills() {
  local co; co="$(mkempty)"
  runco "$co" init >/dev/null 2>&1
  for s in company-setup triage workflow hiring-manager portfolio-strategist; do
    assert_file "starter skill: $s" "$co/skills/$s/SKILL.md"
  done
}

t_init_refuses_overwrite() {
  local co; co="$(mkempty)"
  runco "$co" init >/dev/null 2>&1
  assert_fail "second init refuses to clobber" bash -c "cd '$co' && '$ORCH_BIN' init"
}
