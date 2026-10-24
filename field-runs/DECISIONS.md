# Decision log - lobsters field-run evidence branch

Ordered by decision time (IST, 2026-10-24). Each entry records the
decision, reason, evidence, impact, and reversibility or remaining
uncertainty. No internal agent or tooling identifiers; evidence
pointers are to files on this branch.

## D1 - 08:21 - Expanded study continues past the 09:46 hard stop
- Decision: the 3-app noise + missed-bug study (user's 08:11 scope)
  continues past the earlier 09:46:01 stop; no new artificial
  deadline is promised.
- Reason: the user delegated operating decisions at 08:20:52 and
  closed the approval discussion at 08:21.
- Evidence: this log; stage reports accumulate per app.
- Impact: publication of stage raws continues per the standing
  immediate-push rule.
- Uncertainty: none on scope; per-item data gaps remain proof gaps,
  not permission gaps.

## D2 - 08:21 - Bug lobsters-ed722e44 introducer classified SKIP
- Decision: the MariaDB-era introducing commit b8cc0cef of the
  ed722e44 fix is a SKIP under the different-DB/Ruby skip rule, not
  a HIT or MISS; it is excluded from both denominators.
- Reason: the introducing era cannot be replayed on the approved
  sqlite/Ruby 4.0.0 stack, and no MariaDB exception environment is
  set up.
- Evidence: bugs/lobsters-ed722e449227b39ab6268f4260aaa66df95275bd/
  (regression FAIL-before/PASS-after at the fix PR, era evidence,
  RESOLUTION-20261024.md).
- Impact: preserved fix-regression evidence is retained; the pulls
  API [] result is recorded as "no associated PR returned", not as
  proof of a direct push.
- Reversible: yes, if a MariaDB replay environment is ever approved;
  the entry and raws are retained for that case.

## D3 - 08:21 - Metric definitions chosen
- Decision: adopt METRICS.md - noise = (equivalent + false survivor
  + environment noise) / classified survivors with unresolved
  reported separately plus coverage; HIT requires mutant span to
  intersect mapped fixed lines (no proximity credit); flag
  denominator = added/modified Ruby lines in head coordinates with
  deletions counted separately; all line/class sets recorded for
  recompute; interval method and unit reported transparently as
  author judgment; top rank reports findings.order first, live
  unignored, with group IDs, N/A when no findings.
- Reason: consistent, recomputable definitions chosen under the
  08:20:52 delegation instead of holding the study for approval.
- Evidence: field-runs/METRICS.md.
- Impact: no metric is published until the data lands and is
  recomputed under these definitions; earlier summary numbers stay
  descriptive stage values, not study metrics.
- Reversible: definitions are versioned; any change lands as a new
  METRICS.md revision with a new entry here.

## D4 - 08:20 - Noise selection attempt 1 ruled UNQUALIFIED
- Decision: the first lobsters noise-15 ledger
  (noise/lobsters/attempt-1/) is not a metric selection.
- Reason: its rule added an ancestor-of-pin restriction the user's
  rule does not contain; the skip of PR 2202 on that ground is not
  authorized. The ancestor=NO datum itself was verified live; the
  disqualification is of the rule, not the datum.
- Evidence: noise/lobsters/attempt-1/README.md, SELECTION-RULE.md,
  noise-ledger.csv.
- Impact: collection is redone from the live merged_at-desc
  candidate list at collection time; the 12-map execution queue
  tied to attempt 1 does not run.
- Uncertainty: none; superseded-pending marking stands until the
  corrected ledger lands.

## D5 - 08:20 - EX-1 exclusion requires per-era red verification
- Decision: the user_administration exclusion (EX-1), approved for
  the pin tree where that spec is red, applies to any historical
  tree only after the targeted spec is confirmed actually red in
  that tree; where green it stays in scope.
- Reason: excluding a green test would silently remove live
  coverage and inflate kill rates.
- Evidence: per-tree targeted-spec results to be recorded with each
  replay packet; the 2204/2156 v2 base maps carry a coverage-gap
  qualification until their per-era state is checked.
- Impact: kill-rate claims on v2 rows stay qualified; independent
  verification is checking the per-tree state.
- Uncertainty: open until per-tree results land.

## D6 - 08:21 - Decision logging requirement
- Decision: every decision is documented in this log (timestamp,
  decision, reason, evidence, impact, reversibility/uncertainty).
- Reason: requested by the user at 08:21.
- Evidence: this file.
- Impact: per-app decisions land in packet READMEs and are rolled
  up here.

## D7 - 08:22 - Cross-app metric contract adopted verbatim
- Decision: field-runs/METRICS.md now carries the full cross-app
  metric contract (unit rules, four resolved classes, unresolved
  handling and bounds, seeded PR-cluster percentile bootstrap 10000
  resamples seed 20261024 with N/A rules, supplemental Wilson
  descriptive-only, top-ranked-finding rule, verified bug-replay
  requirements and MISS reason classes, flag-rate line/span
  conventions, selection-15 frozen live cutoff rule with PR-number
  tie-break and no old-pin filter, readiness and honest-zero rules);
  field-runs/metric-record-schema.json added as the empty record
  template.
- Reason: one shared methodology across the three apps so every
  recompute uses the same contract; the 08:21 summary was its
  subset and is superseded.
- Evidence: METRICS.md, metric-record-schema.json.
- Impact: the contract is methodology, not results; the schema file
  is an empty template, not executed study data. Counts come only
  from stored verified records.
- Reversible: contract changes land as new revisions with new
  entries here.
