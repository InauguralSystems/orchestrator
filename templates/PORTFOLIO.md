# PORTFOLIO — what we own and why

The map of every repo, its role, and who staffs it. The machine-readable
source of truth is the `repos:` list in `orchestrator.yaml`; this file is the
human narrative around it.

## Categories

| Category | Meaning | Scored? |
|---|---|---|
| product  | The thing everything else exists to build | yes |
| consumer | An app/lib that exercises the product (a forcing function) | yes |
| infra    | Distribution / CI / plumbing | yes |
| sibling  | Deliberately coupled to a checkout; exempt from motion | partial |
| parked   | Silence is healthy; reported, never scored | no |

## Map

<!-- ADAPT: one row per repo, matching orchestrator.yaml. -->
| Repo | Category | What it is | Staffed by |
|---|---|---|---|
| <product-repo> | product | the thing you sell/build | <core dept> |
| <consumer-repo> | consumer | proves the product under real load | <applied eng> |
| <infra-repo> | infra | CI / release / distribution | <release eng> |
| <parked-repo> | parked | legacy, intentionally silent | unstaffed |

## Coverage

What axes of the product are *not* yet exercised by a consumer? Gaps here are
the portfolio strategist's backlog — a product feature with no forcing
function tends to rot.
