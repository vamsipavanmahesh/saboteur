# Harness metrics

Updated every release (see RELEASING.md). Report the numbers; do not
characterize the harness as improving or worse.

Three counters, per release and cumulative:

1. Claims found false by the fresh-context reviewer: behavior claims the
   independent reviewer showed to be untrue after they were reported done.
   Counted per distinct claim (a claim unit is one statement about behavior
   in a CHANGELOG line, README bullet, docs page, PR or report; the same
   statement repeated in two places is one unit).
2. Acceptance failures caught before release vs. reported after release:
   mismatches the acceptance suite caught pre-release, vs. mismatches the
   acceptance suite would have caught that were instead found post-release.
3. PRs where evidence was a summary instead of output: pull requests whose
   Evidence section asserts a result without the pasted command output.
   Counted per pull request at merge time by reading the Evidence section:
   pasted command output counts as output; prose about a run counts as a
   summary.

## Baseline (recorded 2026-10-23)

| Metric | Baseline |
| --- | --- |
| Claims found false by the reviewer | Not recorded (see examples below) |
| Acceptance failures caught before release | 2 (current cycle; first cycle with a suite) |
| Acceptance failures reported after release | Not recorded (no acceptance suite existed) |
| PRs with summary-only evidence | Not recorded (capture starts with the PR template added 2026-10-23) |

No earlier baseline exists for any counter: the acceptance suite, the
claims checker and the PR-template Evidence section were all added on
2026-10-23. Historical numbers are not retro-derived, because the review
findings and the counters measure different units.

Current-cycle count (metric 2, before release): 2, both found by the
acceptance prototype before the next release and unresolved at recording
time - the fx_gap expectation mismatch (expected `gapKind: assertion_gap`
vs. the JSON the CLI emits; current main d14b9da3) and the money_ranking
label mismatch.

Quoted examples behind metric 1 (not a total; overlapping items collapsed):

- 0.11.2 CHANGELOG "ending false survivors": the reviewer showed the fix
  was "presentation-only by design" and the survivor block still printed
  "covered by ./spec/ledger/router_spec.rb[1:1] - ran, still passed",
  which the reviewer called "a false claim of complete coverage"
  (round 4, P0/P7; retracted in 0.12.2's "Corrected" section).
- 0.12.0 CHANGELOG "separate from assertion gaps": "the assertion-gap half
  is a TODO. The CHANGELOG overstates this." (round 4, P5/P7; retracted in
  0.12.2).
- Gap labels after the 0.12.x fixes: for a mutant where "the value did
  change on input 10 (830 vs 840) and the test didn't notice, so it's an
  assertion gap", saboteur reported `input_gap` with `valueDiffered:
  false`, a combination the reviewer showed to be impossible (round 5,
  item 1).
- README "Know the limits" bullet: "still describes the pre-fix behavior
  and recommends re-running with `--test`" (round 5, item 5).

Context behind metric 2's "after release" column (review findings, not
acceptance-suite counts): the external reviewer reported 8 itemized
findings against 0.12.0 (round 4, 2026-10-22: false survivors on
differently named specs; baseline propose blocked; global flags rejected
by subcommands; `--quiet` printing startup lines; gap label from the first
mutant; the input_gap/assertion_gap gap; four small output defects;
docs/changelog corrections) and 6 itemized findings against 0.12.3
(round 5, 2026-10-23: gap label ignoring confirmation tests; survivor block
contradicting confirmation; noisy confirmation output; value signal mostly
absent plus label-slot and "coarse" wording; outdated README limit;
`--quiet` still printing the spec-inference notice). Rounds 1-3 are not
enumerated in a retrievable source.

## How to count going forward

- Metric 1 is counted per reviewer report at release time, one row per
  distinct claim unit, with the claim text and the finding quoted.
- Metric 2 is counted per acceptance scenario failure attributed to a real
  product-or-expectation mismatch, split by when it was found.
- Metric 3 is counted per pull request at merge time from the Evidence
  section, per the definition above.

## 0.12.4 (2026-10-23)

| Metric | This release | Cumulative |
| --- | --- | --- |
| Claims found false by the reviewer | 1, plus 2 partly true (docs/reviews/0.12.4.md: terminal/--quiet gap label contradicts JSON for a value-neutral mutant; README "Flakiness contained" vs "Know the limits" on pr confirmation; docs claim kind/gapKind in the agent JSON, which carries neither (report.json carries kind)) | 1 false + 2 partly true (first recorded cycle) |
| Acceptance failures caught before release | 0 confirmed product failures in the audited window (the 2 baseline cases were frozen contract-decision expectations, resolved; 1 infrastructure incident excluded; the window is not the whole cycle) | Not established from the audited window |
| Acceptance failures reported after release | Not yet applicable (no release exists since the acceptance suite) | Not yet applicable |
| PRs with summary-only evidence | 6 of 7 - merger's own read of the PR bodies, not independently audited (#1318, #1319 no evidence section; #1321, #1322, #1323, #1330 prose about runs without pasted output; #1329 pasted command output) | 6 of 7 (same basis) |

