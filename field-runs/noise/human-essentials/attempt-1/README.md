# human-essentials noise-15 attempt 1 - INVALID SELECTION (independent live audit 08:36-08:37 IST)

Producer bundle preserved verbatim (SELECTION-RECEIPT.md,
api-merged-p1/p2.json, selection.json, DECISIONS.md, bin/). Audit
raw log: verification-20261024T0836IST.txt.

PASS: frozen HEAD e5e69704fc49babacb2684bf846560dcb2e63988 == live
branches/main; bundle raw pages 141/141 complete, incomplete=false;
live base:main population 129 vs producer git 128 reconciles via the
documented 5709 merge-sha quirk (PR 5709's merge_commit_sha
6aa0d2cc is the 'Merge pull request #5719' commit; 5635 and 5720
verified stacked on non-main bases). No old-pin filter.

FAIL - wrong eligibility filter: the producer's git-based rule counted
PRs with app/** changes that are NOT Ruby. Live /pulls/N/files shows
5 of the 15 selected have ZERO app//lib .rb files: 5743 (.erb +
spec), 5721 (docs only), 5602 (.erb + specs), 5695 (.erb only),
5604 (.erb + specs). Under the user rule ("touching app/ or lib/
Ruby") they are ineligible, and 5 eligible PRs were missed.

Independent recomputation (discrepancy evidence, NOT a replacement
selection - the regeneration owned by the producing run): true live merged_at-DESC
eligible-15 under the anchored ^(app|lib)/.*\.rb$ filter:
5723, 5742, 5656, 5727, 5541, 5722, 5386, 5274, 5171, 5606,
5628, 5690, 5692, 5686, 5684. Ten of the producer's picks are
correct; 5743, 5721, 5602, 5695, 5604 would be replaced by
5628, 5690, 5692, 5686, 5684.

Impact: no base maps or replays on the 5 ineligible PRs; work on
the 10 confirmed-eligible PRs may proceed once the corrected
ledger lands. The bug-20 candidate list needs the same filter
audit (its test+code signal must require app/lib .RUBY change -
e.g. 5743's erb+spec must not qualify). Bug-stage skip ledger
(13 age skips, 6 unmappable, 1 eligible 5386/5685 pending
regression FAIL/PASS) is recorded in DECISIONS.md as producer
claims, not yet verified; no denominators or scores.
