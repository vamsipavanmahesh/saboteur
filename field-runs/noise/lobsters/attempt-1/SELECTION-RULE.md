# Lobsters noise-15 selection (frozen 2026-10-24T08:19 IST)

Rule: from GitHub search API (repo:lobsters/lobsters is:pr is:merged, pages 1-2, collected 2026-10-24T08:17-08:19 IST), take merged PRs newest-first by merged_at; keep those whose merge commit (pulls API merge_commit_sha) is an ancestor of pin 407536444934ac7d78f4ce1c18f228e3891a8663 AND whose first-parent..merge diff touches >=1 app/**.rb or lib/**.rb (git pathspec wildmatch). Stop at 15. Zero-mutant PRs retained if selected. Full candidate ledger incl. skips: noise-ledger.csv.

Selected 15 (merged_at desc): 2231, 2171, 2172, 2183, 2197, 2182, 2175, 2103, 2205, 2174, 2204, 2178, 2090, 2102, 2073.

Skips (examined, excluded):
- 2202: merge commit 9fefd21b NOT an ancestor of the pin (and 0 app/lib Ruby files)
- 2228, 2180, 2199, 2191, 2176, 2168, 2195, 2196, 2092, 2110, 2207, 2211, 2208, 2212, 2218: 0 app//lib Ruby files in diff (views/config/docs/etc.)
- 2114, 2078, 2075: eligible but below the top-15 cutoff (retained in ledger)
