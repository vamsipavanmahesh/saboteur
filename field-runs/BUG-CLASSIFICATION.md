<!-- Provenance: study-wide bug-replay classification addendum authored by the study lead 2026-10-24 08:42 IST, grounded in the user's original 08:11 bug-replay instructions. Adopted verbatim; extends the metric contract (METRICS.md). Defines classification, not measured results. Consistent across all three apps. -->

# Bug-replay classification addendum

Decision: 2026-10-24 08:42 IST. Original request inspected: October 24 08:11:34 IST bug-fix replay instructions. This addendum defines classification, not measured results.

## Separate candidate selection, verification and replay outcomes

1. Candidate selection uses the stated OR predicates: fix in title, linked issue, or test added with a code change. Apply no Ruby-file filter to bug candidate selection. Keep the first up-to-20 selected candidates in the declared order, including zero-Ruby candidates; do not replace inconvenient rows. A signal establishes candidate eligibility, not a verified bug.
2. Establish actual bug behavior and a regression witness that FAILS before the fix and PASSES after. Record issue intent and relevant code evidence. A title or linked issue alone is insufficient. Missing witness is verification_pending or unverified, never an automatic nonbug or MISS.
3. Map the actual fixed behavior to its introducing change. Inspect all affected source types, including ERB/templates, JavaScript and configuration. A Ruby-only mapping script's empty result is not evidence that no introducing change exists. Preserve fixed old/new ranges, introducing ranges and the mapping method.
4. Apply the explicit older-than-six-month and different-DB/Ruby skip rules separately, after the relevant evidence is available. Unknown age is unresolved, not old. Mixed-age fixes retain component-level ages and identify any replayed young subset; do not describe that as a complete replay of every bug in the fix PR.
5. Run the introducing change with historical tests and the required map/restore checks. Only an eligible, verified, completed replay can enter HIT/(HIT+MISS). Preserve selected-but-skipped, blocked, unverified and mapping-limited cases outside that denominator and publish their counts and reasons.

## Non-Ruby and pure-addition cases

- A verified non-Ruby bug is not automatically excluded. When its causal fixed ranges can be mapped and an eligible historical replay is completed, classify no surviving mutation overlap as MISS/out_of_scope if supported by the actual source/operator scope. Preserve a zero-mutant report and exact scope proof where the introducing change has no mutable Ruby. Do not invent a replay result from an empty Ruby diff alone. Runtime or map failure stays blocked, not MISS.
- No fixed old-coordinate lines (pure addition) means the ordinary blame algorithm has a mapping limitation. Inspect removed/replaced neighboring behavior and earlier introducing edits, and use the regression witness to support a causal mapping if one exists. Do not map a new fix line back by proximity, blame the fix itself as its own introducer, or infer nonbug.
- If no defensible introducing edit/fixed-line correspondence can be established, classify mapping_limited with the attempted evidence. This is neither an age skip nor MISS and remains outside the completed-replay denominator. It remains in the candidate ledger and attrition table.
- Once mappings and a completed eligible replay exist, HIT requires actual mutation edited-span intersection with the mapped fixed ranges. Whole-method spans or nearby lines do not qualify. Other MISS reasons require the same completed evidence gate.

## Flag-rate comparability

Keep the existing primary flag denominator of unique added/modified app/lib Ruby lines, and identify it explicitly as Ruby-line flag rate. Non-Ruby changed lines and counts must be retained separately. Zero Ruby denominator yields N/A, not 0%. A non-Ruby MISS does not have a comparable Ruby-line chance baseline; state that limitation rather than comparing all-bug hit rate to a mismatched line population. Mixed-language and mixed-age subsets must be named.

## Required ledger fields

candidate_rank, predicates_and_evidence, candidate_eligible, bug_verification_status, regression_before_after, source_types, fixed_ranges_old_new, introducing_mapping_status, introducing_sha_or_pr, introducing_age, db_ruby_compatibility, skip_reason, replay_status, authoritative_report, outcome, miss_reason, denominator_included, coverage_limitations.

Current Human Essentials numbers remain provisional candidate/mapping status counts, not verified-bug or MISS counts.
