# Incident review: worker "upstream force-push / 10 vanished SHAs" claim - REFUTED

Worker raw inputs preserved byte-exact (vanished-10-shas.txt,
raw-errors-and-refs-0835.txt, pr2231-base-map-20261024.log,
basemapwatch-2231.log, empty FETCH_HEAD). Merger verification
transcripts: lobsters-sha-diagnosis.txt, sha40-verify.txt,
sha-ancestry-verify.txt.

Verdict (2026-10-24 08:35-08:38 IST, live GitHub API):
- NO upstream force-push or object loss. main HEAD =
  407536444934ac7d78f4ce1c18f228e3891a8663 (the known pin), unchanged.
- All 15 published ledger merge SHAs (noise/lobsters/attempt-3) ==
  live /pulls/N merge_commit_sha (full 40 chars), all commit objects
  exist (HTTP 200 with parents), and all 15 are ancestors of main
  (compare behind_by=0, 15/15).
- The worker-local ledger SHAs (same 8-char prefix, different tail)
  are HTTP 422 upstream - they do not exist on GitHub. Local
  derivation corrupted the tails; cause on the worker side
  (listing/derivation bug), NOT upstream history change. The
  worker's message-grep "(#N) NOT_FOUND" and ancestry "not in main"
  results are local-clone artifacts (partial blob:none clone with a
  failing promisor remote; message-based search is unreliable -
  e.g. 2231's squash subject has no "(#2231)" in its first line).
- Worker worktrees are checked out at the CORRECT published SHAs
  (pr2231 at 9fd8f5fc, base 372345a2 = verified parent
  372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c; tree
  d51d28cbe347364a0c0e0b81caa3436eeec83a99). The 2231 v2 base-map
  raw and other in-flight trees are NOT invalidated; tree identity
  proof: sha40-verify.txt.
- No remapping, no synthetic-SHA cleanup, no discard of preserved
  raws. Worker should repair its local clone (fresh full clone or
  fetch with fixed refspec; git fsck) and regenerate its local
  ledger from the published attempt-3 CSV.

SEPARATE FINDING in the worker's raw log (pr2231-base-map-20261024.log):
the 2231 base run crashed exit 70 - saboteur internal error
Errno::ENOENT on its own progress file
(/tmp/saboteur-progress20261024-19094-vvwtpy) in
Diagnostics#painted_file_glyphs (diagnostics.rb:389), at 4/11869
mutants, wall 285.49s, rss 490232 KB. Baselines (882 examples, 2
checks) and the coverage map (741 subjects) completed first;
BOUNDARY_STOP_MAP_CACHED at 08:27:54. This is a saboteur crash bug
candidate (diagnostics kills the run when its progress tmpfile
disappears), reported to the study lead for issue filing. The crash
is in the mutation phase; the cached map's usability is for the
worker to confirm.
Minor datum caveat: skip-row PR 2202's API merge_commit_sha is not
an ancestor of main (compare diverged, behind_by=1) - merged
elsewhere or history note; 2202 stays excluded on its 0-Ruby-file
ground either way.

## Root cause confirmed 08:38 IST (study lead + producer)

The 10 wrong full SHAs were not produced by any tool or derivation
bug: their 32-char tails were typed by hand from remembered 8-char
prefixes - fabricated identifiers. The original attempt-3 ledger
was always correct (consistent with the merger's 15/15 live audit).
Every "not our ref" / 422 came from those invalid typed IDs; there
was never a force-push, object loss, or hash collision. The real
objects resolve after unshallowing the worker's partial clone;
trees for 2175/2178/2158 were never actually created and are being
rebuilt programmatically from the ledger. The 2231 worktree is at
the correct 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8 (raw proof
packet pending from the worker).

Cost accounting: the alarm window is 08:34 -> 08:38 IST (~5 min) on
the record; the worker's "25 min loss" figure is not grounded in
any earlier timestamped evidence. No user-facing alarm was sent.

Procedural rule now in force (study-wide): opaque identifiers
(SHAs, digests, IDs) are read from source programmatically, never
typed from memory; an exact 40-char check against source runs
before any execution that binds a tree. The invalid commands and
outputs remain preserved above for audit.

## 2231 base-run outcome correction + crash cause context (08:39 IST)

Overall outcome of the pr2231-base run is EXIT 70 (internal crash),
NOT a pass and NOT a clean MAP_BOUNDARY_STOP. The baselines (882
examples, 2 checks) and coverage map (741 subjects) completed and
the map cache was written (BOUNDARY_STOP_MAP_CACHED 08:27:54); the
cache may remain usable, but the run record is the exit-70 crash.

Cause context from a read of the pinned source (0.12.3, 6f87ccc9):
@progress_file is a Tempfile (diagnostics.rb:294) read back by path
in painted_file_glyphs (line 389), called from finish_progress
(lines 322-330), which runs from an ensure in Engine#run_candidates
(engine.rb:325-326). No explicit signal trap exists in these paths;
on an interrupt, tempfile unlink during unwinding can precede the
ensure-path read. Timing (boundary stop 08:27:54, crash ~5 s later)
is consistent with that interrupt-cleanup race; external tmpfile
removal cannot be excluded from the log alone. Filed as issue #1347
(https://github.com/vamsipavanmahesh/saboteur/issues/1347);
checked against #1346 (summarizer UTF-8 crash) - not a duplicate.
