# DESIGN — why Orchestrator is built the way it is

Orchestrator runs a software company as an autonomous loop on top of a coding
agent. This is the *why* behind the mechanics — the design rationale and the
epistemology it rests on. The mechanics themselves (hooks, gates, the work loop,
the CLI) live in [ARCHITECTURE.md](ARCHITECTURE.md) and the [README](../README.md);
this document is the reasoning that makes them a *system* rather than a pile of
features.

---

## 0. The premise: nobody is right 100% of the time

No developer and no coding agent is correct every time. That is the one axiom
everything here is built on. The architecture never assumes correctness — it
assumes **error**, and engineers to catch and correct it. It is built for the
world that exists (fallible actors) rather than the fantasy of an agent that is
always right. Everything below is a consequence of taking that seriously.

## 1. Proof, not belief

If no believer is reliable — human or agent — then you cannot trust *belief*.
You can only trust *proof*: a check against reality (a test that runs, a
benchmark that measures, a build that compiles). So the system never asks the
agent "is this right?" and trusts the answer. It asks reality.

Which means **the quality of the output lives in the verification, not in the
generator.** The agent proposes; reality disposes. What ships is exactly what
survived a check — no more, no less. (§8 shows the striking consequence: swap the
agent for a weaker or stronger one and the *quality* doesn't move, because
quality was never in the agent.)

## 2. The metric is recovery, not accuracy

Accuracy caps below 100% for everyone, so "be more accurate" is a race no one
finishes. **Recovery** — how fast and cheap a wrong result is caught and
corrected — has no ceiling. A system that is right 95% of the time and catches
the other 5% in minutes beats one that is right 99% and ships the 1% silently.
Orchestrator optimizes the thing that can reach 1 (recovery), not the thing that
can't (accuracy). The whole stack is a **net** of independent checks whose job is
to make being wrong *survivable* — caught early, corrected cheaply, never shipped
silently.

## 3. The stack — replace "remembering" with "mechanism"

Every layer is the same move: take something that depended on a human (or agent)
*remembering* to do it, and make it mechanical and unavoidable.

### 3.1 Hooks — the floor

Deterministic code, run by the harness, that the model **cannot talk past**. A
*guideline* lives in a prompt and is advisory (the model may ignore it); a
*guardrail* lives in a hook and is enforced. Orchestrator ships three
(`orchestrator hook`):

- **deny-guard** (PreToolUse) — blocks the irreversible: force-push/delete of a
  protected branch, `rm -r` of a home/root path.
- **stop-gate** (Stop) — a turn cannot end with a red gate on a dirty tree; the
  loop keeps fixing instead of stopping on red.
- **roster-sync** (PostToolUse) — the committed roster stays identical to the live one.

Rules of the floor: it is *defense in depth, not a security boundary*; each rule
is **incident-shaped** (added because something actually broke — guardrails cost
false positives, so you don't add them speculatively); it has an escape hatch
that ideally **expires**; and it lives **outside the reach of the thing it
guards** (a guard the loop can edit is no guard). What *must* hold goes in a hook;
everything else is a guideline.

### 3.2 Gates — the verifier, for ~free

A gate answers the question that would otherwise route to a human: *"did I break
it?"* and *"is it actually faster?"* Verification is deterministic — a test run
costs ~zero agent tokens — so a gate replaces an expensive human judgment (or an
unreliable agent self-assessment) with a cheap, reliable check. Two tiers,
because a change makes two kinds of claim:

- **Correctness — binary, rules-based.** The regression/build/test gate.
  Rules-based feedback ("which rule failed and why") is the strongest,
  most-actionable form of verification, and far more reliable than asking a model
  to judge its own work.
- **Performance — statistical.** One run is noise. The `perf-gate` runs the
  benchmark **n=5**, takes the median and the full spread, and **passes only on a
  confirmed, non-overlapping speedup.** n=5 vs n=5 with complete non-overlap is a
  permutation test: under the null, the probability of that separation by chance
  is 1/C(10,5) = **1/252 ≈ 0.4%** — a valid empirical proof, stronger than the
  p<0.05 bar science runs on. Overlap means "not real yet."

The two are **coupled**: a performance claim needs *both* — proven-faster *and*
proven-still-correct. A faster wrong answer is not a speedup (it is often faster
*because* it skips the work it should do).

A gate also **hardens** code, it doesn't only check it. To measure you must
**run** the code (n=5 = ten real executions = a soak test with a timer);
performance changes are the highest-risk *correctness* changes there are (a fast
path that must behave identically to the slow one); and a tight, reproducible
distribution is a **determinism signal** — a wide or overlapping spread flags
nondeterminism (a heisenbug) that a single green run hides. One instrument catches
two lies.

### 3.3 CI — continuous and unattended

A proof you have to *remember to run* is still half-advisory. CI runs the proofs
automatically, on every change, whether anyone remembers or not — it is to the
gates what the hook is to the deny-guard. The "continuous" is literal: the proofs
run continuously, so "proven, not guessed" holds on *every commit*, not just when
someone measures.

### 3.4 The flywheel — capture the *why*, then promote it

When a break is finally fixed, the valuable output is not the patch (the cheap
last keystroke) — it is the **root cause**: *why it failed at first*. The why is
what the expensive debugging tokens actually bought, and it is the only part that
generalizes to the whole class. So the fix-cost is an *investment*: capture the
why and you pay for that failure class **once**; amortized, its cost trends to
zero. That is what makes the system *improve over time*.

Two disciplines keep the capture trustworthy:

- **The why must be the real why, not the plausible-but-wrong one.** A
  confidently-wrong root cause is worse than none — it is a false causal model
  welded into a skill, and everything built on it compounds the error. So a
  captured why is **proven by a test that fails without the fix and passes with
  it.** That single act proves the why is real, promotes the note to a mechanical
  check, and prevents recurrence — even the learning is ground-truth-verified.
- **Promote load-bearing gotchas up a ladder:** a **skill note** (advisory — the
  agent tends to avoid it) → a **regression test** (it cannot *silently* recur) →
  a **hook** (it is mechanically impossible). A system that only *notes* gotchas
  gets wiser; one that *promotes* them gets harder.

The proven surface is the CI suite, and CI keeps every past proof running for
free, forever — so the surface only grows and never retreats.

## 4. The loop

`orchestrator work` is the autonomous cycle:

```
report to the Chief of Staff → route work → owner does it (gated + reviewed)
  ↳ backlog dry?  → research (propose): surface candidate gaps
        → adversarially review each with diverse lenses (kill hallucinated ones)
        → real gap? route it, continue   → genuinely dry? WRAP honestly, stop
  hits a decision? → research the best approach first
        → how / reversible / within vetoes?               → decide, proceed
        → whether / irreversible / outward-facing / spend? → escalate, pre-researched, one rec
```

Design commitments in the loop:

- **Honest halt, not make-work.** Zero new work is a valid outcome; the loop
  wraps rather than manufacturing churn. But because the halt is *model-judged*,
  it is backed by a **deterministic bound** — a max-iteration / wall-clock /
  spend cap plus a repeated-failure circuit-breaker — so control never depends on
  the model choosing to stop. The bound is also a *cost* control: it cuts losses
  when the loop is spending expensive fix-tokens on a break that won't go green.
- **Reframe on stuck.** Repeated failure is met with neither more patching nor
  immediate termination. The loop **reframes** — it stops trying to fix and asks
  *"why did it fail?"*, moving the model into a different region of its output
  distribution (a diagnostic mode) where the root cause the fix-loop was
  tunneling past becomes reachable. The reframe is a *library* matched to the
  failure class: *"why did it fail?"* (general), *"reason about it
  geometrically"* (nondeterminism / memory / timing bugs, whose causes are
  spatial — layout, boundaries, windows — not logical). Only if reframing also
  stalls does the bound terminate.
- **Adversarial review is a filter, not a verifier.** A panel of diverse-prompt
  skeptics is good at killing *hallucinated* candidate gaps — different prompts
  explore different regions of the model's distribution and decorrelate *framing*
  errors. But they share the model's *priors*, so they cannot be the trusted
  check (a model judging its own work is the weakest form of verification, and
  models reliably miss their *own* errors). Review filters candidates on informed
  opinion; the **gate** — rules-based, run against reality — is what actually
  verifies. **Trust the gate over the review.**

## 5. The escalation boundary is the axiom boundary

Some things are proven *outside* a system and asserted *within* it. Relativity
does not prove the constancy of *c* — it takes it as a postulate, asserted
within, established empirically outside. You cannot prove *c* inside the theory
that assumes it, and you don't need to.

A **gate is a postulate.** It encodes an invariant proven outside (by
measurement — n=5, a golden output, a baseline) and asserted within the loop,
which never re-derives it. This is what makes the loop *bounded and trustworthy
rather than circular*: a real proof sits under each constant.

Who may establish a constant? Establishing one means **proving** it — empirically
— not asserting it. An agent can measure, so an agent can prove, so an agent can
**establish new constants** (do science), not merely operate inside given ones —
bounded by the *proof standard*, not by its identity. The line was never
human-vs-agent; it is **proof-vs-guess**. What remains irreducibly human is only
the constants **no measurement can prove** — terminal *values*: what to want,
what to optimize for, which product to build. Those are asserted by choice,
legitimately, because there is nothing to measure; everything *downstream* of a
value is provable.

> **Escalate the value; prove the rest.** The human is the value-source, not the
> axiom-source.

## 6. Error correction: recoverable, not perfect

A wrong constant "poisons" everything asserted within it — but only in a
*deductive* system, where a bad axiom is internally consistent and never
self-contradicts. In an *empirical* system, a wrong constant collides with
reality downstream: it eventually has to lie to a measurement, and a gate goes
red, an invariant check throws, a benchmark won't reproduce. Reality does not
respect your axiom. So wrong constants are **recoverable** — there are many
downstream chances to catch them.

This is the **error-correcting-code** posture (its origin — the EigenScript
`invariant_qec` example — is not an accident): you don't prevent all errors, you
guarantee enough detection and correction downstream. The measurement net *is*
the error-correcting code. Consequences:

- An agent can establish **provisional** constants and let reality correct them —
  which is how science actually works. Certainty isn't required before building; a
  good-enough proof plus a dense net is.
- **Earlier is cheaper** (the prod-vs-dev cost curve). Coverage *density* sets the
  real blast radius, and the flywheel makes catches happen earlier over time — so
  the system gets *safer as it grows*, not by erring less but by catching sooner.
- The honest floor: **the net isn't 100% either.** So — defense in depth
  (independent checks that fail in different ways), growing coverage, and a
  nonzero-but-shrinking residual that is *named*, not pretended away. Pretending
  100% at any single layer is itself the unrecoverable failure: the silent one,
  with no net beneath it.

## 7. The economics

- **Verification is ~free; generation and repair are the tokens.** A gate run is
  a deterministic command — zero agent tokens. Tokens are spent only where
  reasoning is required: writing and fixing code. The stack puts the cheap half
  (checking) on the deterministic side and reserves the expensive half (thinking)
  for the actual product work.
- **Capability is a cost lever, not a quality lever.** Quality is set by the gate
  (fixed); a model's capability shows up as its **hit rate** — how often its first
  hypothesis survives the gate. A stronger model converges in fewer iterations; a
  weaker one takes more, to the *same* gated quality. The gate protects quality in
  both directions: a weaker model cannot ship *worse* work (the gate blocks it) —
  at worst it stalls or costs more. "No output," never "bad output."
- **Pick the model by `p/h`, not by capability.** Total cost ≈ price-per-token ÷
  hit-rate. A cheaper model with a lower hit rate can be *cheaper overall* when its
  price discount beats its hit-rate penalty. So route by task difficulty: the
  cheap model for the easy majority (its hit rate is already high there), the
  frontier model for the hard tail (a low hit rate makes iterations explode).
  Above a convergence floor, model choice is an *economic* decision, not a quality
  one.
- **Coverage buys model-independence.** Because quality lives on the *gated*
  surface, growing coverage (the flywheel) makes the system *more* model-invariant
  over time — the measured surface expands, the model-dependent surface (raw
  judgment, un-instrumented decisions) shrinks, and you're freer to run cheaper
  models.

## 8. The moat is the measurement

The through-line: **quality lives in the net, not the model.** The clean test of
that claim is to change the model and see if quality moves. It doesn't — swapping
the underlying agent across capability tiers leaves the *quality* of what ships
unchanged, because quality was never in the agent. Capability changes the *hit
rate* (efficiency), not the output. That is the property you want from a moat: it
is **model-agnostic, and becomes more so as it grows.** It survives every model
change — up, down, sideways — because the moat is the measurement, not the model.

## 9. The through-line: invariant preservation

The whole system is one idea wearing several hats, and it originates in
EigenScript, whose name is the tell: *eigen* is the characteristic **invariant**
of a self-transformation, and its founding question — "an observer with no
outside" — is a self-map, whose invariants *are* its eigenstructure. A **constant
and an invariant are the same thing**, one algebraic and one geometric (an
eigenvalue and its eigenvector).

Read that way, every layer is invariant-preservation:

- the **observer / measurement** reads the invariants,
- **n=5** checks an invariant holds *under perturbation* (a heisenbug is
  precisely a value that is *not* invariant across runs — a state that is not an
  eigenstate),
- the **gate** checks an invariant is preserved (correct) or broken (regression),
- the **geometric reframe** reasons in the basis where a broken invariant is
  *visible* as a shape instead of smeared into noise,
- the **hooks** protect the invariants that must never break,
- and error correction (`invariant_qec`) restores an invariant knocked off by a
  perturbation.

EigenScript ships this as `lib/invariant.eigs` (`invariant_stable` throws the
moment a value leaves its eigenstate). **Orchestrator is `invariant.eigs` at
company scale:** invariants proven-outside and asserted-within (the gates),
preserved by the loop, deviation caught by the observer, and only the
establishment of a *value* reserved for a human.

## Honest edges (collected)

Because *naming the residual* is a design rule here, not an afterthought:

- **Coverage is the boundary of every guarantee.** "Proven, not guessed" holds on
  the gated surface; off it a failure is *unobserved* — neither proven-absent nor
  caught. Confidence is bounded by instrument coverage, which grows but is never
  total.
- **The net isn't 100%.** Defense in depth and growing coverage shrink the
  residual; they don't erase it. Some errors escape any finite net.
- **A capability floor exists.** Below it, hit rate is too low to converge and the
  loop stalls (the circuit-breaker fires); the `p/h` economics apply only *above*
  the floor.
- **Some sourcing is interpretive.** The autonomy-slider / "keep-it-on-a-leash"
  framing that motivates parts of this is mapped by inference onto documented
  practice; the *verifiability principle* underneath it — systems automate fastest
  where the generation→verification loop is cheap and resettable — is the
  load-bearing, well-supported part.
- **Numbers age.** Specific figures (circuit-breaker thresholds, model
  false-negative rates, per-mode hook precedence) come from fast-moving sources;
  re-check against current docs before hard-coding.

---

*One line: nobody is right 100% of the time, so build for graceful wrong — prove
instead of believe, verify with the cheap deterministic half and spend tokens on
the expensive creative half, catch fast and correct downstream, capture the* why
*and promote it, compound the net, and reserve for a human only the values no
measurement can settle. Everything else is mechanics.*

## Grounding

The verification, permission/hook, autonomy-bounding, and context findings are
grounded in primary Anthropic sources — *Building Effective Agents*, *Building
agents with the Claude Agent SDK*, *Effective harnesses for long-running agents*,
*Effective context engineering for AI agents*, the Claude Code permissions/hooks
docs, and the *Claude Code auto mode* write-up — plus Karpathy's *verifiability*
essay for the generation→verification principle. Claims traceable to those; the
n=5 permutation-test figure is arithmetic; the model-invariance result is from
direct observation and is reproducible by swapping the underlying model.
