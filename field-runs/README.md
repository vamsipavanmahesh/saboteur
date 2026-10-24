# Rails field-run evidence

## Current progress (October 24, 2026, interim - not final study results)

Lobsters noise-block rows completed and strict-qualified: 5 of 45 (PRs 2231, 2204, 2157, 2156, 2171; per-row packets under apps/lobsters/reports/).

Interim summary (per-gap noise is the primary rate unit since 2026-10-24 11:21 IST; per-mutant shown as secondary; verified = survivors with independent triage/verification receipts):

| PR | mutants | killed | survivors | gaps | verified | out-of-scope files |
| --- | --- | --- | --- | --- | --- | --- |
| 2231 | 4 | 4 | 0 | 0 | - | none |
| 2204 | 22 | 19 | 3 | 1 | 3/3 | none |
| 2157 | 11 | 5 | 6 | 1 | 6/6 | extras/routes.rb |
| 2156 | 7 | 6 | 1 | 1 | 1/1 | none |
| 2171 | 2 | 2 | 0 | 0 | - | none |
| total | 46 | 36 | 10 | 3 | 10/10 | 2 PRs affected |

Gap detail: 2204's 3 survivors group on app/models/story.rb:777 (is_gone? boundary); 2157's 6 group on app/controllers/stories_controller.rb:184-190 (meta_tags); 2156's 1 is settings rename (line 51). All 10 survivors resolved as real gaps: 2204 and 2156 by independent new-test kill proofs (tool-verification/verify-packet-2a), 2157 by fresh independent triage (pr2157-independent-triage). Noise so far: 0/3 gaps = 0% descriptive (per-mutant secondary: 0/10); no interval until the full 15-row block. Out-of-scope scan for all 15 selected PRs: apps/lobsters/reports/out-of-scope-scan-20261024.md.

Review follow-ups closed 11:27 IST: the one open crash kill (2204's RecordInvalid kill on story.rb:777) is verified a REAL KILL in isolation (original 33/0, mutant 33/33, restored 33/0; tool-verification/verify-packet-3/). The 2204 inclusive run's 490s engine vs ~48min wall discrepancy is published with cause UNKNOWN (engine CLOCK_MONOTONIC vs external wall; ~39.9min accumulates only in unobserved stretches; reports/pr2204-confirm-all-inclusive/timing-receipts.md).

Pacing change (adopted, tool-documented design): the whole-suite map will be built on a main snapshot and reused for PRs merged within ~2 weeks, with the snapshot SHA recorded per PR and per-PR time measured. Compatibility follows the tool's CI rule: the PR tree must share the snapshot's Gemfile.lock + saboteur config (cache key = hash of those + commit SHA, restored by prefix); the whole-suite-map-v2 pointer is written by whole-suite builds explicitly for later scoped runs whose tree has drifted (docs/ci-whole-suite-map.md, lib/saboteur/engine/coverage_store.rb at pin 6f87ccc9). Spec drift between snapshot and PR degrades confirmation toward the specs the PR run loaded, disclosed per row. Three further rows (PRs 2172, 2183, 2197) are planned deviation-tier under DECISIONS.md D50 (a CSS Baseline lint spec excluded because those era trees carry a genuine 37-minute upstream violation window; suite-completeness deviation only). Nine Lobsters rows are not yet executed; Chatwoot and Human Essentials are in baseline validation. No overall noise rate, 95% interval, or missed-bug conclusion is claimed at this stage. Decision history: DECISIONS.md (D33-D50).

Current human-readable report: REPORT.md and REPORT.pdf (30 pages, snapshot06:49 IST October24,2026).

Original four-hour stopped-window records remain under apps/ and REPORT-historical-* without fabricated saboteur identities. New main-pinned Lobsters evidence is isolated under runs/2026-10-24-main-6f87ccc9/. The report front matter supersedes historical release-wait and CGI attribution claims. Solidus historical evidence is retained; new Solidus execution is out of scope.

Current source pin6f87ccc98377bf0c23f3cf409006f0464c2aa67c, gem0.12.3. CGI setup artifact is corrected; banning-email baseline failure remains. (Superseded claims removed 2026-10-24 11:15 IST: completed map/mutation/replay/triage verdicts now exist for five Lobsters PRs, and scoped exclusions are on record in DECISIONS.md.)

The raw JSON/logs, replay notes, source helper scripts and report-tool checks are retained. REPORT-historical-* is archival; REPORT-update-20261024-0649.md is the current scope/status. MANIFEST.sha256 covers every file except itself. Raw application evidence paths are indexed in the PDF and report appendices.
