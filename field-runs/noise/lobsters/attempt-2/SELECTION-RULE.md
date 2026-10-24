# Lobsters noise-15 selection (attempt 2, CORRECT RULE; frozen 2026-10-24T08:21 IST)

Supersedes attempt 1 (08:19), which wrongly required merge commits to be ancestors of the old pin 40753644 - that was never the user's rule. Attempt-1 ledger preserved at noise-ledger-attempt1-UNQUALIFIED.csv.

Rule: from GitHub search API (repo:lobsters/lobsters is:pr is:merged, pages 1-2, collected 2026-10-24T08:17-08:19 IST), take merged PRs newest-first by merged_at; keep those whose first-parent..merge diff touches >=1 app/**.rb or lib/**.rb (git pathspec wildmatch). Stop at 15. No pin-ancestry condition. Zero-mutant PRs retained if selected. Cutoff verification at 2026-10-24T08:21 IST: lobsters main FETCH_HEAD = 407536444934ac7d78f4ce1c18f228e3891a8663 (clone is current) and search is:merged merged:>2026-10-04 returned 0 results, so no merged PR newer than the candidates is missing.

Selected 15 (merged_at desc): 2231, 2171, 2172, 2183, 2197, 2182, 2175, 2103, 2205, 2174, 2204, 2178, 2090, 2102, 2073.

Skips (examined, excluded):
- 2202: 0 app//lib Ruby files in diff
- 2228, 2180, 2199, 2191, 2176, 2168, 2195, 2196, 2092, 2110, 2207, 2211, 2208, 2212, 2218: 0 app//lib Ruby files in diff
- 2114, 2078, 2075: eligible but below the top-15 cutoff (retained in ledger)

Blocked rows (selected but not runnable on available stack; kept, NOT replaced):
- 2102 (merge 34e7ca10): pre-sqlite era, MariaDB/trilogy required (schema.rb has 78 :unsigned refs)
- 2073 (merge 18d3df8f): pre-sqlite era, MariaDB/trilogy required
