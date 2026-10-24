# Lobsters noise-15 selection ATTEMPT 3 (CORRECT, exhaustive; frozen 2026-10-24T08:26 IST)

Supersedes attempt 1 (UNQUALIFIED, pin filter) and attempt 2 (INVALID, incomplete enumeration: pages 1-2 by created-desc missed 15 in-window merged PRs). Both preserved.

Enumeration: GitHub search API repo:lobsters/lobsters is:pr is:merged merged:>=2026-04-24, per_page=100, page 1: total_count=95, incomplete_results=false, 95/95 returned = exhaustive for the 6-month window (raw: candidates-page1-raw.json). Live-cutoff verification 08:21: lobsters main FETCH_HEAD = 40753644 (clone current); is:merged merged:>2026-10-04 = 0 results.

Merge-SHA resolution: ledger pulls-API SHAs (rate-limit era) + git timestamp correlation of merged_at to first-parent commits (+-90s, provenance column per row). 63/95 resolved; 32 unresolved ALL merged <= 2026-07-06, below the selection cutoff - no selection impact (noise-ledger-v3-unmatched-belowcutoff.txt).

Rule: sort 95 candidates by merged_at DESC (tie-break: PR number); keep those whose first-parent..merge diff touches >=1 app/**.rb or lib/**.rb (anchored regex ^(app|lib)/.*\.rb$; spec files do NOT count); stop at 15. Zero-mutant PRs retained. Blocked rows kept, not replaced.

SELECTED 15 (merged_at desc): 2231, 2157, 2156, 2171, 2172, 2183, 2197, 2182, 2175, 2103, 2205, 2174, 2204, 2178, 2158.
All 15 are sqlite-era ruby 4.0.0 (2158 verified: 0 unsigned refs in schema.rb, .ruby-version 4.0.0; others verified earlier). NO MariaDB-blocked rows in the corrected selection.

Below cutoff (eligible, ranked 16+): 2090, 2143, 2134, 2136, 1927, 2102, 2073, 2078, ... (full ledger). Skips: 0-file rows in ledger. Datum discrepancies vs merger audit: 2182 app/lib count = 1 (story.rb; its other changed file is spec/helpers/users_helper_spec.rb, not app/lib) vs merger's 2 - eligibility unchanged; 2078 = 13 by anchored git diff vs merger's 3 - below cutoff, no impact.
