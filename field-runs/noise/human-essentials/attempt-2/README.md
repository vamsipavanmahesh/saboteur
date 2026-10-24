# human-essentials noise-15 attempt 2 - QUALIFIED (matches merger's independent live audit)

Noise-15: 5723, 5742, 5656, 5727, 5541, 5722, 5386, 5274, 5171,
5606, 5628, 5690, 5692, 5686, 5684 - EXACT match (set and
merged_at-DESC order) with the merger's independent live
recomputation of 08:37 (verification-20261024T0836IST.txt in
attempt-1/). Eligibility of the five new members verified live by
the merger then: 5628=1, 5690=2, 5692=2, 5686=7, 5684=1 app/lib .rb
files. Frozen HEAD e5e69704fc49babacb2684bf846560dcb2e63988.

Attempt-1 root cause (worker receipt): git diff-tree -m diffed
merge commits against BOTH parents, leaking main-side changes into
file lists and falsely qualifying 5 zero-Ruby PRs; fixed to
git diff sha^1 sha; tool-flag semantics misread, no result
inspection involved. Attempt-1 artifacts preserved
(selection-attempt1-INVALID.json; attempt-1/ README stands).

Bug-20 v2 ledger (worker claims, regressions PENDING - no verified
denominator, no scores): 2 eligible-pending (fix 5386 <- introducer
5685; fix 5685 <- introducer 5563, ancestry+date chains claimed
verified by the worker, merger verification pending when packets
land), 3 unmappable_no_fixed_lines (5743, 5695, 5681), 15 B2-age
skips. Merger spot-check: 5681 is a pure addition
(export_request_service.rb +6/-0) - no old-coordinate lines to
blame, consistent with unmappable. Bug-candidate scope rule
(decision D28): candidates enter by the user's three signals as
written (fix title / linked issue / test+code); app/lib-Ruby is NOT
a candidate requirement; candidates without fixed Ruby lines
resolve to UNMAPPABLE. 5743/5695 entered via linked-issue only -
their retention as unmappable is consistent with that rule, not a
contradiction.
