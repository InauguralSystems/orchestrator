# PORTFOLIO — the coverage map

Owned by `portfolio-strategist`. Which areas of the company's work have a repo
actively exercising them, how success in each is validated, and which areas
nothing covers yet. Refreshed on every portfolio review (`orchestrator
propose`). The machine-readable repo list is `repos:` in `orchestrator.yaml`;
this file is the strategy layer over it.

## Categories

| Category | Meaning | Scored by `health`? |
|---|---|---|
| product  | The thing everything else exists to build | yes |
| consumer | An app/lib that exercises the product | yes |
| infra    | Distribution / CI / plumbing | yes |
| sibling  | Deliberately coupled to a checkout; exempt from motion | partial |
| subsidiary | A child company; its own `reports/latest.md` verdict is rolled up (GREEN→ok, YELLOW→warn, RED→fail) | rollup |
| parked   | Silence is healthy; reported, never scored | no |

## Covered areas

<!-- ADAPT: one row per area of your product/company that a repo actively
     stresses. "How success is validated" is the house contract's yardstick —
     ideally something external, not self-declared. -->
| Area under stress | Repo | How success is validated | Ledger |
|---|---|---|---|
| <core area> | <consumer-repo> | <external spec / benchmark / user outcome> | GAPS.md |

## Uncovered / candidate lanes

<!-- This is where the strategist parks the next-repo candidates. Status:
     UNCOVERED (open lane), PARTIAL (touched but not stressed), BLOCKED (waiting
     on other work — record the blocker, don't propose around it). -->
| Area | Status | Notes / candidate shape |
|---|---|---|
| <area nothing exercises> | UNCOVERED | candidate: <repo shape>, oracle: <external yardstick> |
| <area waiting on other work> | BLOCKED | blocked on <milestone>; highest yield when unblocked |

## Review log

<!-- `orchestrator propose` appends a dated line each review: what was refreshed,
     the ranked lanes, and the one proposal (or the zero-proposal verdict). -->
- <date> — map seeded.
