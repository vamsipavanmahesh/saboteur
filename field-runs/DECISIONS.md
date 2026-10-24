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

## D28a - 08:42 - Bug-candidate classification corrected
- Amendment to D28: candidates enter by the literal three signals
  with no file-type filter (5743/5695 are eligible candidates);
  "unmappable" requires actual no-mapping proof across ALL fixed
  lines incl. .erb, else replay triage with out_of_scope MISS as
  the expected evidence-backed outcome; linked issues must be
  verified actual bug reports; candidate population and verified
  denominator stay separate; "2 eligible" not final.

## D29a - 08:42 - 2231 v2 kills PROVISIONAL; cache-miss rule
- Amendment to D29: the 4 kills / 0 survivors are PROVISIONAL and
  do not qualify the 2231 noise row (map created, not consumed).
  Rule: any cache-miss row is rejected as a full-BASE-protocol row.
  Miss mechanism diagnosed from pinned source (settings digest over
  integration/require/rspec_args/rails/tests/coverage_recorder);
  exact differing key not derivable from published raws - worker
  reconciles settings and reruns; no selected-spec fallback.
  identity-proof.txt mutants=0 extraction corrected (actual 4).

## D30 - 08:42 - Bug-replay classification addendum adopted
- Decision: field-runs/BUG-CLASSIFICATION.md is the study-wide
  classification contract (candidate/verification/replay separation;
  no Ruby filter on candidates; regression witness required; ERB/JS/
  config mapping inspected; pure-addition = causal investigation
  before mapping_limited; Ruby-line flag rate named, non-Ruby N/A;
  required ledger fields; all counts provisional).
- Impact: HE's "unmappable" cases reopen for ERB blame and
  regression work per this contract; consistent denominators across
  lobsters, chatwoot, human-essentials; no zero-mutant fabrication,
  no auto-exclusion.

## D31 - 08:46 - Bug outcome unit: one verified behavior per fix PR

- Decision: Adopt the study lead's bug-unit addendum verbatim (field-runs/BUG-UNIT.md). Primary unit = one behaviorally verified bug record per fix PR; splits only with pre-registered distinct witnesses; dominant-introducer-first is scheduling only; HE #5692's two blame records resolve to one PR #5587 replay; component HIT witness != completed aggregate rate; dedup flag lines per introducing PR.
- Reason: Fixes can blame to multiple introducing commits; counting per blame record would inflate denominators and mix units.
- Evidence: BUG-UNIT.md; HE ledger v3 (20 candidates: 13 mechanical old-only, 7 pending-regression, all denominator_included=false, outcome=null - provisional, not audit-verified; referenced line-maps/blame receipts not in packet, worker to send).
- Impact: All bug rates are per-verified-behavior with aggregate fix-PR counts beside; component table kept separate from primary denominators; pooled flag rate deduplicated per introducing PR.
- Reversibility: Contract addition; any later split requires pre-result recorded witnesses.

## D32 - 08:46 - Whole-suite map protocol fixed at the pinned source

- Decision: Adopt PROTOCOL.md as the required replay route: per-era unscoped map job (writes map + inputs snapshot + whole-suite-map-v2 pointer), then pr-preset replays with partial_coverage="use" in the same root with identical config; honest per-row labels (cache hit / partial-merged with provenance / full fallback). Canary on PR 2231 (merge commit 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8) precedes all noise-row execution.
- Reason: The three v2 replays consumed 44/81/1-test selected-spec maps and could not confirm survivors; survivor confirmation reads only the pointer-named whole-suite map (engine.rb:299-311 at the pin).
- Evidence: PROTOCOL.md mechanism claims verified against saboteur 0.12.3 pin 6f87ccc9 (coverage_store.rb, coverage_map.rb:302-309, coverage_partial.rb, partial_invalidation.rb:24,45, selection_announcement.rb:62, engine.rb:390-392, docs/ci-whole-suite-map.md); the worker's packet sources are byte-identical to the pin blobs.
- Correction logged: an earlier staging-side reading required the map to be built at the BASE tree specifically; that was over-specific. The user's words require whole-suite completeness with the era tree's specs, which the documented map-job route satisfies. This is a main-agent correction of an internal interpretation, not a change to user intent.
- Impact: 2231/2204/2156 v2 rows remain PROVISIONAL until re-run; no noise-row execution before canary raws show HIT + active confirmation on 2231; the same route applies to chatwoot and human-essentials.
- Reversibility: Protocol document; rows re-run under it replace provisional rows as new labeled evidence, raws preserved.

## D33 - 08:49 - B2 six-month cutoff confirmed as the frozen request-anchored day boundary

- Decision: CONFIRM the existing METRICS.md (08:22) definition: B2 "older than 6 months" uses the frozen request-anchored window with day boundary 2026-04-24T00:00:00+05:30, identical to the population freeze. Not a new choice; a per-fix-relative reading is not the contract. The day boundary (not 08:11:34 exactly) is preserved deliberately for population stability.
- Reason: The user's 08:11 words ("from the last 6 months" / "Skip if it's older than 6 months") name one shared window; a rolling per-fix anchor would make the rule incomparable across candidates.
- Evidence: field-runs/noise/human-essentials/BUG-LEDGER-V3-CUTOFF-INVARIANCE.md - full recompute of the 20 HE line-map raws: classification invariant for any cutoff in (2026-03-13, 2026-05-29]; 13-old/7-pending holds exactly.
- Impact: HE bug ledger v3 temporal classification qualified as audited (13 B2-old, 7 pending-regression) with the #5171/doc-line/spec-line caveats recorded; lobsters and chatwoot bug lanes use the same frozen boundary at blame time.
- Reversibility: Definition confirmation; raw raws preserved for recompute under any cutoff.

## D34 - 08:55 - Verifier forecast corrected to observed stage; no cause claimed

- Decision: Record the verifier's corrected schedule from observed progress, superseding the 08:45 and 09:10-09:15 forecasts: PR 2204 inclusive (no-EX1) replay measured at 425/861 examples, pace ~47 examples/min at 08:54; first 2204 result ~09:15, 2156 ~09:40, remaining reruns ~09:50, full corrected packet ~09:55 (all uncertain, stage-based).
- Reason: The earlier forecasts were estimates; the correction is grounded in the observed example counter and pace. The worker's resource-contention hypothesis is UNPROVEN - the box's own load average is ~1; main has requested quota/process-stage evidence before any restart or reordering. No cause is recorded here.
- Evidence: verifier progress report 08:54 (425/861, ~47 examples/min); box load observation.
- Impact: No publication or qualification waits on the stale 09:10-09:15 packet expectation; canary raws for 2231 remain the gating evidence for noise-row execution. The user has been told no noise row is qualified yet.
- Reversibility: Forecast record only; further corrections append new entries.

## D35 - 09:13 - Executed bytes verified as the pin; lock checksum deviation contained

- Decision: The canary M/R pair proceeds with the as-run Gemfile.lock FROZEN (no mid-pair edits); the executed gem (7f5b8949) is proven byte-identical to pin 6f87ccc9 (tool-verification/2026-10-24-executed-gem-vs-pin.md: 238/238 files identical, 0 missing). The lock's stale registry checksum (234ee503) is a documented reproducibility caveat, fixed only after run R via bundler against the isolated local artifact source (no manual hash edit).
- Reason: Lock content is a cache key input; mid-pair correction would invalidate the map provenance and waste the running map. Executed bytes, not lock text, are authoritative for what ran (user's 06:46 build-from-pin instruction).
- Evidence: byte-level diff result above; worker's 09:12 tree-audit packet (vendored == installed artifact).
- Impact: Canary provenance closed on the artifact question; the lock checksum fix is scheduled before the general 15-row stage, whose rows then record the corrected lock sha256. No app-repo Gemfile/Gemfile.lock changes leave the evidence branch (instrumentation diff is field-run-local, never a product PR).
- Reversibility: Lock fix is a normal bundler regeneration; pre-fix rows keep their executed-byte proof.

## D36 - 09:23 - Correction: scoped replays cannot consume the whole-suite map for selection (merger error owned)

- Decision: PROTOCOL.md corrected. In 0.12.3 a --since replay structurally cannot HIT or partial-merge the whole-suite map: spec inference rebinds config to {"tests" => inferred specs} BEFORE the coverage fetch (selection_announcement.rb, scope_to_guesses - verified at pin 6f87ccc9), so the settings digest differs by exactly the tests key (M 240ea092 vs R f66619fb, both snapshots reproduced) and the partial guard (tests empty) refuses by design. The whole-suite map's role in scoped runs is pointer-only: survivor presentation (review C1) and SurvivorConfirmation (#1063). A scoped replay with the pointer present IS the documented CI diff-mode flow.
- Reason (error owned): my earlier audit asserted "inference never writes config['tests']" - my grep looked for direct assignment and missed the config.with rebinding. The worker's mechanism report is verified correct at the pin.
- Evidence: selection_announcement.rb (pin-identical local diff); M/R input snapshots (root ab27afb4, runtime 712bc81a, seed 1 identical; settings differ only by tests); R argv verbatim in the worker's 09:22 root-cause packet; R v3 map_key 13af8ec9 identical to v2's (deterministic).
- Impact: 2231 v3 ran the CORRECT intended flow (scoped selection + pointer present, cache on); with 0 survivors, confirmation was vacuous and no confirmation receipt exists. 2231's ONLY remaining gate is crash-kill cause verification (4/4 crash-class kills). No "0% noise" claim: 0 classified survivors = 0/0 undefined, and a fake kill would flip a mutant to survivor. The known-survivor canary (2204 or 2156) must produce actual pointer presentation + confirmation receipts before the 15-row stage. The earlier "PROVISIONAL because selected-spec map" framing is revised: the violation in v1/v2 was the ABSENT whole-suite pointer map, not scoped selection itself.
- Reversibility: Document correction; published raws unchanged.

## D37 - 09:25 - PR 2204 inclusive confirmation accepted as QUALIFIED PARTIAL; rejected-kill class handled by tool

- Decision: The verifier's 2204 inclusive whole-suite packet (861 examples, no EX-1) is published and accepted as a qualified partial row: 22 mutants = 16 Killed / 0 Survived / 6 rejected kills, exit 0. The 6 RuntimeError verdicts are UNRESOLVED (tool-rejected: killing tests fail on unchanged code with a Domain-collision RecordInvalid); the three earlier scoped "survivors" fall inside this set and are no longer survivor candidates. Accepted crash kill 21af923e (same RecordInvalid class) is flagged for the verifier's specimen rerun before per-mutant settlement; the row-level score is insensitive to that outcome.
- Reason: Independent merger audit of the attached report JSON + log matched every verifier count; the tool's own unchanged-method check caught the pollution class (fake-kill guard working as designed).
- Evidence: apps/lobsters/reports/pr2204-confirm-all-inclusive/ (RAWS.sha256); open items 1-3 in its README (21af923e rerun, complete:false semantics, 490s-vs-48min timing gap).
- Reversibility: Publication only; raws immutable.

## D38 - 09:33 - PR 2231 replay v3 QUALIFIED (first row, 1/45); crash-kill gate closed by independent verification

- Decision: The 2231 v3 replay row is qualified. All four crash kills are genuine, proven by the independent tester's V2 packet (12 paired runs, original-PASS / mutant-FAIL / restored-PASS, mutations applied from the tool's own report.json, immutable artifact 7f5b8949, era tree 9fd8f5fca9). Noise is 0/0 = UNDEFINED (never 0%). The survivor-confirmation mechanism remains unproven (vacuous at zero survivors) and gates the 15-row stage via the known-survivor canary.
- Reason: Merger audit of the raw packet found every gate met; the producer's prose-only packet was rejected as evidence earlier and is superseded.
- Evidence: apps/lobsters/reports/pr2231-crash-kill-verification/ (README-AUDIT.md + PUBLISHED-MANIFEST.sha256; artifact gem referenced at runs/2026-10-24-main-6f87ccc9/artifacts/, hash re-verified).
- Reversibility: Publication only; raws immutable.

## D39 - 09:41 - HE doctor attempt 1 contaminated (registry gem); kept as env-timing sample only; pin fix verified in shape, receipt gaps listed

- Decision: The first HE doctor run (08:55-09:35 IST, exit 3, 300s deadline) used registry saboteur 0.12.3, not the pin (unchecked vendored-copy failure + bundle install without --local). It is published as a correction + incident with the raw retained as an environment-timing sample ONLY. No HE baseline/map/replay/count exists. The fixed route (vendored artifact 57ac8099 + bundle install --local, claimed 0-path payload diff) is accepted in shape; the payload-diff command + both roots (or installed-vs-artifact sha256 lists) and ruby -v are required receipts before the fixed doctor run, because the same-GEM_HOME reinstall-skip mode would leave registry bytes in place undetected by bundler's own output.
- Reason: Registry 0.12.3 differs from the pin in 18 lib files; any timing or behavior under it is not attributable to the pinned tool.
- Evidence: noise/human-essentials/doctor-20261024-0941/ (RAWS.sha256).
- Reversibility: Publication only; raws immutable.

## D40 - 09:46 - Known-survivor canary 2204-c1: survivor-confirmation PROVEN; general noise-stage execution GO

- Decision: The survivor-confirmation mechanism is proven from raws (whole-suite map consulted via pointer c091018a; covering specs outside the inferred selection actually executed; 3/3 confirmations ran and passed). General noise-stage execution may begin; per-row gates (M-side receipts in the row archive, kill-cause verification, noise triage) remain per-row. The 15-row stage no longer has a mechanism gate.
- Reason: R's executed set includes search_spec examples unreachable from the 81-test scoped selection; the only source of that coverage is M's whole-suite map. Base parent verified independently via the GitHub API (merge ed722e44's sole parent = 8f1b5006).
- Evidence: apps/lobsters/reports/pr2204-canary-c1/ (README-AUDIT.md); survivor/HIT scope separation and the two-scope UNRESOLVED-vs-confirmed distinction recorded there.
- Reversibility: Publication only; raws immutable.

## D41 - 09:49 - "--since X --all" runs all tests but writes no whole-marked pointer; 2156 partial qualified with survivor UNCONFIRMED; D37 semantics corrected

- Decision: The verifier's inclusive runs (2204, 2156) executed all tests with no whole-suite-map-v2 pointer; survivors from such runs are UNCONFIRMED candidates by the tool's own declaration. 2156 (7 mutants: 6K 1S 0 rejected, 865 examples, no EX-1, base parent API-verified) is published as a qualified partial with survivor 84a2b3ca16355339 unconfirmed pending a pointer-bearing bridge or per-ID proof. D37's 2204 packet carries the semantic correction (numbers unchanged; no survivor semantics were exercised there). The 2204-c1 canary's mechanism proof (pointer present) is the only whole-confirmed survivor evidence so far.
- Reason: Running all tests and having whole-marked pointer coverage are different tool states; only the pointer enables survivor confirmation (#1063) and whole-suite presentation (C1).
- Evidence: apps/lobsters/reports/pr2156-confirm-all-inclusive/; pr2204-confirm-all-inclusive/README.md correction; tool-verification/2026-10-24-verifier-lock-receipt.txt (verifier lane 4-tree additions-only lock proof; path-source runtime caveat retained).
- Reversibility: Publication only; raws immutable.

## D42 - 09:49 - HE selection v3 + bug ledger v5 QUALIFIED (one unresolved mapping); v2 superseded and preserved

- Decision: HE noise-15 (unchanged, boundary-clean) and bug-20 (common ANY-3: +5723/5709/5602/5604, -5685/5633/5681/5674 by rank push-out, 5693 invalidated -> 5689 backfill) are qualified. 5709 stays in the population as unresolved_mapping (API merge_sha names PR #5719's merge - stack conflation), not excluded, not backfilled past 20. Ledger v5: 12 B2-old / 7 pending-witness / 1 unresolved / 0 verified bugs / 0 denominators. Corrected script set approved (watch4 byte-identical to the reviewed reference; owned-PID observers; fail-closed pin/artifact gates; jobs=1; real exit codes; aware datetimes).
- Reason: Merger-independent population arithmetic + live-API spot checks + ledger count verification all matched; the v1/v2 contaminations (diff-tree -m; mixed-offset string dates) are documented and preserved as superseded, not deleted.
- Evidence: noise/human-essentials/attempt-3/ (README-AUDIT.md).
- Reversibility: Publication only; raws immutable.

## D43 - 10:08 - Kill-cause gate = closed 10-of-36 seeded sample; all-kill cause verification exceeds the user contract

- Decision: The kill-confidence gate for lobsters noise rows is the seeded 10-of-36 sample, now closed 10/10 (8 assertion + 2 crash/RuntimeError, 0 fake/timeout/DB). Remaining kills keep tool-reported classes with the sample as the stated confidence basis. No all-19/all-36 per-kill cause requirement.
- Reason: The user contract (08:11:34, verbatim re-read) requires fresh-context triage of EVERY survivor, a 95% interval, top-finding real-gap verdicts, and every number recomputable from files - it does not require per-kill cause verification at any count. The sample was our own added gate; extending it to every kill adds cost without a contract basis (user delegated such calls 08:20:52).
- Evidence: tool-verification/verify-packet-2a/, verify-packet-2b/ (raws + audits).
- Reversibility: If any future kill shows anomaly signs (fake-kill suspicion, red-credited kill), that row is held and its causes verified individually per the standing fake-kill rule.

## D44 - 10:09 - PR 2204 row QUALIFIED WITH DISCLOSED DEVIATION; strict-era rerun not required; ledger keeps two explicit tiers

- Decision: PR 2204's noise row is resolved as QUALIFIED WITH DISCLOSED DEVIATION: 22 mutants (18 assertion + 1 crash + 3 survivors), 3/3 survivors REAL GAP (independent bump-free proof), row noise 0/3 = 0%, top finding 56ec2857eb8103bd REAL GAP, 3 survivors = 1 finding group (Story#is_gone?, story.rb:777). The producer lock's brakeman/matrix bumps are a disclosed environment deviation with unassessed impact on kill counts; survivor-side evidence is bump-free. No strict-era rerun: the user-contract outputs (survivor triage, noise, top-finding verdict, recomputability) do not depend on the bumped gems, and the kill-confidence gate closed via the 10-sample (D43). The row reopens if an anomaly implicates those gems.
- Reason: Main's explicit ruling request; user delegation 08:20:52; holding a finished row for a rerun whose outcome cannot change any contract number would be fake work.
- Ledger tiers (explicit, consistent from here): STRICT-QUALIFIED rows = 1/45 (2231). QUALIFIED-WITH-DEVIATION rows = 1/45 (2204). Rows with complete evidence = 2/45. No per-app interval or overall claim until each app's noise block completes.
- Evidence: apps/lobsters/reports/pr2204-replay-v2/ (row), pr2204-canary-c1/ (bridge), tool-verification/verify-packet-2a|2b/ (triage + sample).
- Reversibility: Deviation reopen rule stated above; publication only.

## D45 - 10:10 - 2204 lock-bump impact source-assessed NIL; row STRICT-QUALIFIED; ledger tiers updated

- Decision: After reading the actual upstream diffs (matrix v0.4.2...v0.4.3 = comments + version only, zero executable change, sole era dependent capybara unaffected; brakeman v8.0.5...v8.0.6 = scanner internals only, never required by app/spec code, load-only via Bundler.require), the 2204 producer lock bumps are assessed NIL-impact. PR 2204 moves from QUALIFIED-WITH-DEVIATION to STRICT-QUALIFIED. The lock-preservation process violation stays disclosed (conservative-versions gate going forward).
- Reason: Main's correction of the earlier unproven claim required source grounding; the assessment now provides it. Matrix cannot change any outcome (no behavior delta); brakeman's delta is unreachable from the test path (verified by code search at the era tree).
- Ledger (explicit): STRICT-QUALIFIED = 2/45 (2231, 2204). QUALIFIED-WITH-DEVIATION = 0. Complete-evidence rows = 2/45. Descriptive row metrics unchanged: 2204 noise 0/3 = 0%, 3/3 real_gap, top finding 56ec2857eb8103bd (one finding group, story.rb:777); PR-cluster 95% N/A (<2 informative PRs); no per-app interval until the 15-row lobsters block completes.
- Evidence: diffs read live from ruby/matrix and presidentbeef/brakeman; era lock c63fe92b0212003b9a25acf3c1d39fed5c2d8900d9d10947370f765a6b4c9950 (sha256 matches the fetched ed722e44 Gemfile.lock).
- Reversibility: Assessment reopens if new evidence shows a load/execution path was missed.

## D46 - 10:13 - PR 2157 row STRICT-QUALIFIED; ledger 3/45 strict

- Decision: PR 2157 noise row is STRICT-QUALIFIED: 11 mutants (5 genuine kills: 2 assertion + 3 exception; 6 confirmed survivors all REAL GAP, one meta_tags finding group, mutant-level 6), row noise 0/6 = 0% descriptive, top finding 5cacdbc3d0bc508e REAL GAP (factual findings.order first). No environment deviation (era-original lock + additions only; pinned artifact byte-verified three ways).
- Reason: Producer bridge confirmation (all 6 survivors "confirmed" in the report records) and the independent tester's raw triage align completely; every kill cause verified; provenance gaps closed earlier (binding chain + gapfix receipts).
- Evidence: apps/lobsters/reports/pr2157-map-replay-c1/ (+ map-artifacts/, gapfix/), apps/lobsters/reports/pr2157-independent-triage/.
- Ledger: STRICT-QUALIFIED = 3/45 (2231, 2204, 2157); QUALIFIED-WITH-DEVIATION = 0. No per-app interval or overall claim until the lobsters 15-row block completes.
- Reversibility: Publication only; raws immutable.

## D47 - 10:24 - PR 2156 row QUALIFIED WITH DISCLOSED DEVIATION (producer-tree lock unreceipted); upgrade path = bounded-lock backfill

- Decision: PR 2156 noise row qualifies with one disclosed deviation: map+replay+bridge+triage all verified from raws (7 = 6K + 1 confirmed REAL-GAP survivor; bridge actual - pointer-sourced requests/settings_spec.rb confirmation; kill IDs == verifier frozen pool; binding chain verified), but the producer's 2156 tree lock is unreceipted (headmap2 preamble gap). Survivor classification is bump-free via the verifier lane; producer kill set carries the caveat. Strict admission on the 2157-style posthoc bounded-lock backfill.
- Reason: Evidence closes every load-bearing gate except environment receipting for the producer tree; holding the row entirely would waste valid triage, hiding the gap would violate the lock-preservation rule.
- Ledger: STRICT = 3/45 (2231, 2204, 2157); WITH-DEVIATION = 1/45 (2156); complete evidence = 4/45.
- Reversibility: Publication only; upgrade on backfill receipt.

## D48 - 10:26 - 2156 lock backfill verified; row STRICT-QUALIFIED; ledger 4/45 strict, 0 deviation

- Decision: The 2156 bounded-lock backfill closes D47's remaining gap (merger-verified additions-only diff from full bytes; bounded lock byte-identical to 2157's verified bounded lock). PR 2156 is STRICT-QUALIFIED.
- Ledger: STRICT-QUALIFIED = 4/45 (2231, 2204, 2157, 2156); QUALIFIED-WITH-DEVIATION = 0; complete evidence = 4/45. No per-app interval until the lobsters 15-row block completes.
- Evidence: apps/lobsters/reports/pr2156-map-replay-c1/lockbackfill/.
- Reversibility: Publication only.

## D49 - 10:55 - PR 2171 row STRICT-QUALIFIED (0 survivors, noise 0/0 undefined); ledger 5/45

- Decision: PR 2171 is STRICT-QUALIFIED: 2 mutants both killed (1 assertion + 1 crash/RuntimeError), 0 survivors, 0 rejected; noise 0/0 UNDEFINED per the metric contract; top finding N/A. First headmap3 row with full preamble receipts (lock/bundle-list/version).
- Note: merge order != PR-number order verified via API (2171's merge 9a773eac predates 2156's d9998c25); study row order follows merged_at DESC as specified.
- Ledger: STRICT-QUALIFIED = 5/45 (2231, 2204, 2157, 2156, 2171); complete evidence = 5/45. 10 lobsters rows not executed.
- Evidence: apps/lobsters/reports/pr2171-map-replay-c1/.
- Reversibility: Publication only.

## D50 - EX-2 exclusion: spec/css_widely_available_spec.rb in exactly three lobsters era trees (PRs 2172, 2183, 2197)

- Date: 2026-10-24.
- Scope: lobsters rows for PRs 2172, 2183, 2197 only. Not applicable to any other row or app. The 15 selected PRs are preserved (no replacement, no skip).
- Decision: Exclude spec/css_widely_available_spec.rb from the whole-suite baseline/map/mutation runs of exactly these three rows. Era application code, CSS, and lockfile are preserved byte-for-byte; only the spec file is omitted from execution (14 examples). All three rows are classified QUALIFIED-WITH-DEVIATION, deviation = suite completeness; "whole existing suite" is never used unqualified for these rows.
- Why (source-proven causality, NOT external database drift):
  - The failing assertion concerns app/assets/stylesheets/application.css:296 ("word-break: break-word").
  - That line was added by PR 2196's merge commit 1251ff78fe9d1aa8b6197f399b8889f402dc09d0 (2026-09-14T00:48:23Z) and removed 37 minutes later by direct commit e2ef864fc8dbe2a4885d7dac911ef3b7565088be (01:25:58Z, "word-break deprecated in favor of overflow-wrap #2196").
  - PRs 2197 (merged 00:51:04Z), 2183 (00:54:58Z), and 2172 (01:00:34Z) are the only three selected rows merged inside that window; every other selected row merged outside it and runs green on this spec. Upstream mainline itself was red on this spec during exactly that 37-minute window.
  - The web-features entry css.properties.word-break.break-word has baseline: false with byte-identical by_compat_key in releases v3.37.0 (2026-09-03), v3.38.0 (2026-09-10, live at era), v3.39.0 (2026-09-17), and the current next release (2026-10-22). The verdict was the same at era as now; no published web-features release makes these trees green, so a historically faithful data fixture cannot rescue them. The earlier era-rot hypothesis (external DB drift) is retracted.
- Coverage impact: In the published PR 2171 whole-suite coverage map (975e4b71e35bdae529738d845b23b38450e35d95d24e78273b7eb8e20d4d7c4a), this spec's 14 examples reference zero Ruby subject lines, supporting the expectation that the exclusion is coverage-neutral. This is evidence from a neighboring era tree, not proof for these three trees: each affected row packet must verify its own as-run exclusion inputs and row-specific relevant coverage when its map is available, and must state this limit explicitly. No extra era run is performed solely to prove per-tree neutrality.
- Preserved evidence: The original PR 2172 baseline attempt (exit 5, no mutants, spec red on both head and base) remains published as an invalid attempt with head/base failure receipts.
- Verification required in each affected row packet: effective exclusion as-run; omitted-example count (14 expected); head/base tree digests unchanged apart from the exclusion mechanism; row-specific coverage check of the exclusion; explicit deviation-tier labeling.
- Reversibility: Publication only.
