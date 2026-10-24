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

## D8 - 07:14 - Whole-app map2 mutation phase truncated
- Decision: stop the extra whole-app mutation phase after its map
  cache completed (117/11984 mutants observed, exit 130).
- Reason: ETA exceeded the then-current window.
- Effect: map stage "partly", no aggregate mutation score; partial
  verdicts are not full-app results. (Backfilled from author log.)

## D9 - 07:16 - map2 clock discrepancy preserved unresolved
- Decision: keep both values (envelope span 1213.27s vs wrapper
  502.41s) with no causal stall or timeout-accounting claim.
- Reason: later aligned probes do not explain the earlier window.
  (Backfilled from author log.)

## D10 - 07:31 - map3 uncontended build, stopped at map boundary
- Decision: run an uncontended map build and stop at the map
  boundary (295.52s through boundary); not a pure coverage phase.
  (Backfilled from author log.)

## D11 - 07:43-07:52 - v2 supported-base-map rebuilds for 2204/2156
- Decision: rebuild legitimate PR-base maps and restore supported
  cache artifacts; v2 counts unchanged, all four survivors remain
  unconfirmed at edited lines; other three original replays remain
  scoped; no universal product failure inferred. (Backfilled.)

## D12 - 07:49 - Kill-cause classification requirements
- Decision: do not accept kill-cause classification from operator
  name or killed count alone; corrected lock-pinned reruns with
  verbose logs/JSON required; earlier non-lock-pinned evidence
  preserved with its limitation. (Backfilled from author log.)

## D13 - 07:56 - Privacy-safe environment/stage records
- Decision: publish qualified stage records with "partial" labels
  where warranted; raw originals retained separately; no private
  identifiers in published artifacts. (Backfilled from author log.)

## D14 - 08:12 - Three apps in parallel, measured runs isolated
- Decision: run lobsters, chatwoot, human-essentials in parallel
  with each app's measured runs isolated; no cross-app contention
  in reported timings; no finish-time promise. (Backfilled.)

## D15 - 08:22 - Bug-eligibility window and timestamp conventions
- Decision: six-month window anchored 2026-04-24 (original request
  2026-10-24); PR eligibility by merged_at; introducing-commit age
  by committed timestamp, authored timestamp preserved when
  different. (Backfilled from author log.)

## D16 - 08:22 - Zero-mutant PRs retained
- Decision: zero-mutant results stay zero-mutant with score N/A,
  not coverage success; rates require verified eligible completed
  denominators. (Backfilled from author log.)

## D17 - 08:23 - Noise attempt 2 ruled INVALID SELECTION
- Decision: attempt 2 (noise/lobsters/attempt-2/) is not adopted;
  merger live verification found 7 eligible in-window PRs omitted
  (2157, 2156, 2158, 2143, 2134, 2136, 1927) and 2 count-datum
  mismatches (2182, 2078). Corrected collection pending; execution
  queue against attempt 2 halted. See attempt-2/README.md.

## D18 - 06:52 - EX-1 original decision record (backfill)
- Decision: exclude only spec/features/user_administration_spec.rb
  via rspec_args for field runs; no app spec edits; the CGI failure
  was a runtime artifact, not a second exclusion.
- Evidence: user approval 06:52 (WhatsApp) and pin-baseline red
  state; scoped to verified-red trees per D5.

## D19 - 08:25 - Chatwoot noise-15 selection QUALIFIED
- Decision: adopt noise/chatwoot/attempt-1/ as the chatwoot metric
  selection after merger live verification: develop HEAD
  98a9ed710ad7334b07e96ca6c1da0b7e8ebc686a exact match; full window
  enumeration (33 PRs) found zero omissions; 15/15 selected file
  lists and 25/25 skip file counts verified live.
- Evidence: noise/chatwoot/attempt-1/verification-20261024T0825IST.txt.
- Impact: chatwoot replays may proceed against this selection; the
  producer's environment deviations (PRODUCER-DECISIONS.md) ride
  with every chatwoot packet.

## D20 - 08:25 - Authority-prose caveats corrected
- Decision: retract the earlier caveat that "user rule B2" was not
  user-sourced. The user's 08:11 scope message contains the
  different-DB/Ruby skip rule verbatim (section B.2) and the
  start-with-2204 instruction; "suite or the directories you'll
  use" is from the user's Oct 23 21:37 task message; EX-1 from 06:52;
  delegation from 08:20:52. All producer authority phrases are now
  traced to user-channel originals.
- Impact: bug-1 SKIP and the chatwoot baseline narrowing stand on
  user-sourced rules, not only on delegated resolution. Published
  caveats in decision-sources/README.md and the bug-1 RESOLUTION
  file revised; raws byte-preserved.

## D21 - 08:26 - Chatwoot selection downgraded to PROVISIONAL
- Decision: no noise-15 population is qualified until the study
  lead's own audit receipts pass; chatwoot attempt-1 README amended
  QUALIFIED -> PROVISIONAL. The merger's live-API verification
  (all PASS) stays on record but does not alone qualify.
- Reason: author audit found the git-log-#N freeze method invalid;
  a live API merged_at population cross-check is required before
  any expensive maps.
- Impact: chatwoot and human-essentials queues stay halted;
  lobsters attempt-2 remains invalid pending attempt-3.

## D22 - 08:26 - Chatwoot selection re-qualified on merger reconciliation
- Decision: chatwoot attempt-1 is the qualified noise selection.
  Live merged_at-DESC eligible-15 matches the packet order exactly;
  window/skip/eligible-below counts fully reconciled (see packet
  README). D21's blanket downgrade is narrowed: qualification now
  rests on the merger's live-API proof, not on pending external
  receipts. Below-window zero-ruby rows not itemized by the worker
  are recorded as informational-only.

## D23 - 08:28 - Lobsters noise-15 selection QUALIFIED (attempt 3)
- Decision: adopt noise/lobsters/attempt-3/ as the lobsters metric
  selection: exhaustive 95/95 enumeration, zero in-window
  omissions, order verified live as merged_at DESC, merge SHAs
  match. Selected: 2231, 2157, 2156, 2171, 2172, 2183, 2197, 2182,
  2175, 2103, 2205, 2174, 2204, 2178, 2158.
- Corrections recorded: the merger's 08:23 order was not a strict
  sort (worker order correct); 2182 app/lib count is 2 not 1; 2078
  count divergence is a diff-base difference, both bases recorded.
- Impact: replay queue proceeds; practical-reuse execution order is
  logged separately from selection rank and is not metric bias
  since all 15 are included.

## D24 - 08:28 - EX-1 scoped to red trees only; 2204/2156 v2 maps superseded
- Decision: targeted user_administration spec is GREEN at the 2204
  and 2156 base trees (5/0), so EX-1 must not apply there; the v2
  EX-1 base maps are superseded (preserved, labeled not
  full-era-suite); corrective no-EX1 replays queued. EX-1 remains
  valid only at the pin tree where the spec is red.
- Impact: no published row may claim whole-era-suite coverage from
  v2 maps; earlier v2 survivor rows keep their unconfirmed status
  and gain this coverage-gap label.

## D25 - 08:38 - Lobsters "force-push / vanished SHAs" claim refuted
- Decision: treat the worker's claim as a local artifact, not an
  upstream incident. Live API: all 15 published merge SHAs match
  merge_commit_sha (40/40 chars), all objects exist, all are
  ancestors of main (behind_by=0); the 10 worker-local SHAs are 422
  upstream. No remapping; no raw discard; 2231 v2 tree identity
  valid. Worker repairs its partial clone and regenerates its local
  ledger from the published CSV.
- Evidence: incidents/2026-10-24-lobsters-sha-claim/.
- Side finding: 2231 base run crashed exit 70 (saboteur
  diagnostics ENOENT on its own progress tmpfile at 4/11869
  mutants) after map cached; reported for issue filing.

## D26 - 08:38 - human-essentials noise-15 attempt 1 INVALID
- Decision: HE attempt-1 is not adopted: 5 of 15 selected PRs have
  zero app//lib .rb files live (5743, 5721, 5602, 5695, 5604;
  .erb/docs/spec-only changes); 5 eligible PRs missed. Worker
  regenerates with the anchored .rb filter; the bug-20 candidate
  list needs the same filter audit. Frozen HEAD and population
  reconciliation (141/129/128) verified.
- Evidence: noise/human-essentials/attempt-1/.

## D25a - 08:38 - Root cause of the SHA incident: hand-typed identifiers
- Amendment to D25: the wrong tails were typed from memory, not
  tool-derived; original ledger always correct. New study-wide
  rule: opaque IDs read programmatically from source with an exact
  40-char check before execution binds a tree. Alarm window on
  record: ~5 min (08:34-08:38); "25 min loss" claim ungrounded;
  no user alarm sent.

## D27 - 08:39 - Exit-70 diagnostics crash filed as issue #1347
- Decision: the pr2231-base crash is a product bug (diagnostics
  progress-tempfile ENOENT on the ensure path during an
  interrupted run); filed as issue #1347 with the raw log and the
  pinned-source line references. Not a duplicate of #1346. Run
  outcome recorded as EXIT 70, not pass/boundary-stop; map cache
  may remain usable.
- Note (process): the verifier's corrected-packet forecast moved
  from ~08:45 to 09:10-09:15 (08:29 finding: user_administration
  spec GREEN at 2204/2156 heads inclusively, requiring no-EX1 maps
  for both); stale checkpoints are not reported.

## D28 - 08:41 - HE noise-15 v2 QUALIFIED + bug-candidate scope rule
- Decision: adopt noise/human-essentials/attempt-2/ (exact match
  with the merger's independent live list). Bug-candidate scope:
  the user's three signals as written; app/lib-Ruby is a NOISE
  requirement, NOT a bug-candidate requirement; candidates without
  fixed Ruby lines resolve to UNMAPPABLE. 5743/5695 (linked-issue
  signal, .erb-only) retained as unmappable is consistent, not a
  contradiction. 5681 verified pure-addition (+6/-0), unmappable.
- Impact: HE replays may start on the 10+5 verified PRs once
  baseline lands; bug regressions (5386<-5685, 5685<-5563) pending
  execution; no denominators or scores yet.

## D29 - 08:41 - 2231 v2 replay published with cache-miss qualification
- Decision: the 2231 v2 replay did NOT consume the restored
  whole-suite base map (tool-reported cache miss; own 44-test
  inferred map). Published as a second selected-spec replay, NOT a
  whole-suite-map replay; the restore failure is a recorded
  finding. Kills are tool verdicts; cause classes pending
  independent proof (D12).
