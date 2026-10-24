# Metric definitions (chosen 2026-10-24 08:21 IST)

Chosen by main under the user's 08:20:52 delegation of decisions (user's
WhatsApp message of 08:20:52 IST).
No metrics are computed or published until the underlying data has
landed and been recomputed under these definitions.

- Noise = (equivalent + false survivor + environment noise) /
  classified survivors. Unresolved survivors are reported
  separately, with coverage, not folded into the rate.
- HIT: a mutant's span intersects the mapped fixed lines. NO
  proximity credit.
- Flag denominator: added/modified Ruby lines in head coordinates;
  deletions counted separately.
- All line sets and class sets are recorded with each result so any
  metric can be recomputed.
- Interval: method and unit (PR clustering) reported transparently
  as author judgment, not naive certainty.
- Top rank: report findings.order first, live unignored, with group
  IDs; N/A when there are no findings.
- Skip/partial states are reported honestly; no made-up numbers.
- Selections are metrics only when the selection rule is the one
  authorized for the study (noise attempt-1 under
  noise/lobsters/attempt-1/ is UNQUALIFIED and excluded).
