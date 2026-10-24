# human-essentials selection reconciliation receipt (2026-10-24 08:26 IST)

- Live repo tip at clone 08:14 IST: e5e69704fc49babacb2684bf846560dcb2e63988 (= selection frozen HEAD; verified tip, no pin-ancestry filter).
- API population: search issues is:pr is:merged merged:>=2026-04-24, 2 pages, total_count=141, all 141 items captured (api-merged-p1.json, api-merged-p2.json raw).
- Git population: first-parent commits of frozen HEAD matching merge/squash PR patterns, window >= 2026-04-24T00:00:00+05:30: 128 PRs.
- Diff API-minus-git: 13 PRs (5635, 5642, 5709-5718, 5720). Spot-verified via pulls API: 5635 base=kits-to-kit-items, 5720 base=guide/12-guide-refresh-inventory (stacked, non-main base) => correctly absent from main first-parent history. 5709: API merge_commit_sha 6aa0d2cc resolves to the 'Merge pull request #5719' commit on main (API merge_sha quirk; PR content entered main via #5719) => no missing main PR.
- Diff git-minus-API: empty.
- Ordering check: API merged_at DESC top 25 matches git first-parent order exactly (5743, 5723, 5731, 5742, 5656, 5740, ...). No timestamp ties among candidates; PR-number tie-break never needed.
- Conclusion: git-derived ledger is the complete main population at the frozen cutoff; noise-15 and bug-20 selections stand. Raw API pages + this receipt retained for audit.
