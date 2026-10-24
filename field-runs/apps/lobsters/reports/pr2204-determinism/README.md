# PR 2204 serial determinism reruns (2026-10-24)

Three serial runs of the same scope (--since
8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76, seed 1, --jobs 1): the
original replay (reports/pr2204-replay/) plus reruns det1 and det2
(report-det1.json, report-det2.json).

- Publisher-side independent three-way diff (also pairwise with the
  jobs-2 run and its repeat): all 22 mutant IDs identical and ZERO
  differences in status or killedBy (exact killedBy values) across
  every pair: orig/det1, orig/det2, det1/det2.
- Author's determinism-diff.json records the same three empty diffs;
  compared fields: id, status, killedBy.
- Note on "gap": report.json has no gap-field schema (mutant fields are
  coveredBy, duration, executed, id, killedBy, location, mutatorName,
  replacement, static, status, statusReason, subject, valueDiffered);
  the diff artifact's "gap" line means the 22 mutant-ID sets are
  identical. No gap-field comparison exists or is claimed.
- The det1/det2 assignment between the two received report files is not
  recoverable from content (both verdict-identical); files are
  preserved byte-exact with hashes in MANIFEST.sha256.
- Rerun logs and wrapper measurements arrived in the 07:32 worker
  bundle: logs/pr2204-det1-20261024.log, logs/pr2204-det2-20261024.log,
  measurement.det1.json (wall 33.24s, rss 392648, exit 1),
  measurement.det2.json (wall 33.83s, rss 392680, exit 1). Publisher
  check: log MEASURED footers match the wrapper values exactly;
  wrapper envelope spans recompute to the same wall times. Wrapper
  status remains null / evidence_paths [] (known limitation, raw kept
  immutable; enriched copies still owed by the author).
- Gap comparison: gap-comparison.md (producer) + publisher verification.
  No gap field exists in report.json (schema enumerated) so JSON gap
  is N/A. The TEXT survivor blocks of all five pr2204-family logs
  (serial, det1, det2, jobs2, jobs2-repeat) are byte-identical -
  same 3 digests, same [boundary] label, same hints (publisher diff).
- CI-flow qualification: this evidence is SELECTED-SPEC scope, not
  the requested whole-map CI flow; see
  reports/QUALIFICATION-selected-specs-20261024.md.
- Fake-kill: zero "user_administration" occurrences in either rerun
  report (grep -c = 0); testFiles = spec/models/story_spec.rb only;
  rejectedKills=0; timeouts=0. EX-1 active (user-approved 06:52).
