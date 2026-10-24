# Lobsters noise-15 selection ATTEMPT 2 - INVALID SELECTION (independent live verification 08:23 IST)

Published raw immediately per the evidence rules. This attempt is
NOT a metric selection and MUST NOT drive the base-map/replay
queue. Attempt 1 (noise/lobsters/attempt-1/) stays UNQUALIFIED;
both are preserved for audit.

What passed verification (independent live GitHub checks, raw
log in verification-20261024T0823IST.txt):
- cutoff: search is:merged merged:>2026-10-04 = 0 results, so no
  merged PR newer than the candidates is missing;
- all 45 ledger rows' merged_at values match live;
- the old pin-ancestry filter is gone from the rule (correct fix);
- 2202's exclusion now rests on 0 app//lib Ruby files, which is
  consistent with the user rule.

What FAILED verification:
- 15 merged PRs inside the selection window are absent from the
  ledger entirely; 7 of them have >=1 app//lib Ruby file and would
  enter the selection under the stated rule: 2157 (merged
  2026-09-14T01:32:33Z, 1 file), 2156 (2026-09-14T01:31:17Z, 1),
  2158 (2026-07-18T16:15:00Z, 1), 2143 (2026-07-15T12:40:32Z, 1),
  2134 (2026-07-11T21:13:07Z, 1), 2136 (2026-07-11T21:09:19Z, 1),
  1927 (2026-07-11T15:22:50Z, 13).
- File-count datum mismatches: 2182 ledger=1 live=2 (eligibility
  unchanged), 2078 ledger=13 live=3 (below cutoff, datum wrong).
- Independent recomputation (verification finding, NOT a replacement
  selection): the first 15 eligible under the stated rule appear to
  be 2231, 2171, 2157, 2156, 2172, 2183, 2197, 2182, 2175, 2103,
  2205, 2174, 2204, 2178, 2158 - i.e. 2157/2156/2158 would enter
  and 2090/2102/2073 would drop out. The producer owns the
  corrected collection; this list is discrepancy evidence only.

Consequences:
- The 12 base-map + 13 replay queue started against this selection
  is working an invalid selection; any rows for PRs outside the
  corrected 15 are off-selection work. Rows already published for
  2204/2156/2090 keep their own evidence value but their selection
  membership is undecided until the corrected ledger lands.
- 2102/2073 blocked-row handling (kept, not replaced) was correct
  behavior for those rows; their selection membership is now
  undecided.

EX-1 per-era red-state qualification from attempt-1's README and
decision D5 still applies to every historic tree. Mentions of
"user_administration" in the decision logs are prose references to
the excluded spec file, not score evidence; the fake-kill check
(zero hits) applies to report.json score files, none of which are
in this packet.
