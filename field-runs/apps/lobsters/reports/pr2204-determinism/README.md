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
- Rerun logs and wrapper measurements for det1/det2 were not in this
  packet; they are expected in the worker's next bundle.
- Fake-kill: zero "user_administration" occurrences in either rerun
  report (grep -c = 0); testFiles = spec/models/story_spec.rb only;
  rejectedKills=0; timeouts=0. EX-1 active (user-approved 06:52).
