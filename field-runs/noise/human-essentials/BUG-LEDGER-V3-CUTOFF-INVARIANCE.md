# human-essentials bug ledger v3 - frozen-cutoff invariance proof (2026-10-24 08:49 IST)

Independent audit of the produced bug-ledger.json v3 + 20 line-map/blame raw packets.

## Verified (live API + raw raws)
- All 20 fix_sha values equal the live merge_commit_sha of their PRs (20/20).
- 1,224 blame entries across 20 candidates: rb/non-rb splits match the ledger for 19/20 (#5171 exception below).
- All 7 mapped_young candidates: young blame commit sets exactly match the ledger's introducing commits with matching per-commit line counts (5386: #5685=2, #5643=3; 5685: #5563=41, #5643=191, #5681=30; 5692: #5587=2+3; 5742/5722/5656/5686: 1 each). Every blamed commit is live-verified inside its claimed PR's commit list or equals that PR's merge SHA (#5643, #5563).

## Temporal classification: invariant to the cutoff reading
- Contract (METRICS.md 08:22, confirmed D33): frozen request-anchored window, day boundary 2026-04-24T00:00:00+05:30 (the Friday 6 months before the 2026-10-24 request day; a day boundary was chosen over the exact 08:11:34 time to keep the population rule stable).
- Recompute of all blame raws against the frozen boundary: all 13 B2-age classifications keep ZERO young blamable lines; all 7 mapped_young keep exactly the same young line counts.
- Empirical bound: newest OLD blame line 2026-03-13T15:38:52-04:00; oldest YOUNG blame line 2026-05-29T15:25:15-04:00. Any cutoff in (2026-03-13, 2026-05-29] yields the identical 13-old/7-pending split. The classification is therefore settled independently of the exact timestamp arithmetic.

## Caveats carried (none denominator-affecting; all denominator_included=false)
- #5171: 4 of 34 non-Ruby fixed lines are in an ADDED file (public/partners_template_updated.csv, +4/-0) with null blame; the skip reason must read "B2 for 56 blamable lines + 4 unmappable (added file)", not "all introducers known-old".
- #5742's single young line is a Markdown doc line (docs/wiki/application_overview.md:126, PR #5672): mechanical blame of a doc edit is not semantic bug introduction; no mutation intersection is possible on that component.
- #5722's single young line is an ERB img tag (PR #5689): non-Ruby, same structural note.
- #5681's single mapped line is a spec line (spec/services/exports/export_request_service_spec.rb:22): a spec span can never intersect a mutant edit; moot under B2-old, recorded for completeness.
- #5692's two blamed commits both resolve to PR #5587: one replay, per BUG-UNIT.md.
- #5685 scale: 878 fixed lines, 262 young (#5643 alone 191 Ruby lines). Dominant-first replay is scheduling only; the component table carries all three introducers.

All counts provisional until regression witnesses and replays; this note audits mapping and temporal classification only.
