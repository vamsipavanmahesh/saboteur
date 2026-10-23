# Lessons

One entry per failure that reached the maintainer or an external reviewer.
Format: what happened, root cause (code / test / claim / plan), and the rule
or check that now prevents the whole class. New lessons are appended by the
review-to-checks loop in [agents/review-to-checks.md](agents/review-to-checks.md).

## 1. Confirmation pass crashed with exit 70

- What happened: `Engine` called the private `Scheduler#map`. The unit spec
  used `double("scheduler")`, so the real wiring never ran and the crash
  shipped.
- Root cause: test. Wiring between two real objects was verified with a
  double, not through the real CLI.
- Prevented by: the Wiring evidence rule in AGENTS.md (wiring changes need
  an e2e spec through the real CLI; unit specs with doubles are not
  evidence for wiring).

## 2. CHANGELOG 0.11.2 claimed "ending false survivors"

- What happened: the change was presentation-only by design, but the
  CHANGELOG entry claimed false survivors were ended.
- Root cause: claim. The entry described hoped-for behavior, not measured
  behavior.
- Prevented by: the Claims evidence rules (claims describe measured
  behavior; "presentation only" when true; overstatements get a
  "Corrected" entry) and `rake claims:check` (no `(e2e: ...)` reference,
  no claim). The 0.12.2 "Corrected" section records the fix.

## 3. The first e2e for that fix passed by construction

- What happened: the fixture added `lib/flow.rb`, so `flow_spec.rb` was
  inferred by name; the e2e passed because of the fixture shape, not the
  fix.
- Root cause: test. The fixture was the easiest passing one, not the
  user's situation.
- Prevented by: the Fixtures evidence rule (test-selection fixtures include
  a spec with NO same-named source file; every e2e spec comments the
  real-world case it models) and the `router_pr` acceptance scenario.

## 4. An inferred-spec map was recorded as "whole-suite"

- What happened: a default full run recorded an inferred-spec map as
  whole-suite, producing a false "covered by X - ran, still passed" claim.
- Root cause: code and claim. Provenance of the map was not distinguished,
  and the report text overstated what the covering list meant.
- Prevented by: the Claims evidence rules and the `router_pr` acceptance
  scenario (no map: "survivors unconfirmed", no block contains "ran, still
  passed").

## 5. CHANGELOG 0.12.0 claimed input_gap was "separate from assertion gaps"

- What happened: the claim was written before `assertion_gap` existed. It
  described behavior the code did not have.
- Root cause: claim.
- Prevented by: the Claims evidence rules (`rake claims:check`; the 0.12.2
  "Corrected" section records the fix).

## 6. Gap labels were computed from the initial run only

- What happened: once confirmation ran other specs, the label computed from
  the initial run was wrong.
- Root cause: code. The label did not account for all surviving mutants of
  the statement.
- Prevented by: the Wiring and Negative-check evidence rules and the
  `fx_gap` acceptance scenario (`gapKind`, `valueDiffered` checked on the
  real CLI).

## 7. A feature plan proposed what already existed

- What happened: a plan proposed per-mutant timeouts, PR review comments
  and incremental stats, all of which already existed.
- Root cause: plan. The plan was written without searching the code, docs,
  `--help` output or CHANGELOG.
- Prevented by: the Plans evidence rule (quote what exists; a plan item may
  not describe existing behavior as missing).

## 8. A `--no-color` bug was fixed in one subcommand only

- What happened: the same bug stayed in the sibling subcommands.
- Root cause: code. The fix was not swept across siblings.
- Prevented by: the Sibling-sweep evidence rule (search all siblings; fix
  or list them in the pull request).
