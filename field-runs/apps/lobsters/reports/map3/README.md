# Whole-app map attempt 3 (clean, uncontended) - 2026-10-24 07:31 IST

Command: bundle exec saboteur run --all --verbose --jobs 1 --no-cache
(+ --html/--json reports/map3/...). saboteur 0.12.3 @
6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
407536444934ac7d78f4ce1c18f228e3891a8663, EX-1 active
(user-approved 06:52), jobs 1, no competing work per producer.

Result: TRUNCATED, exit 130, NO score. Log: 908 examples in 108 spec
files, 3 full passes; baseline checks 1-2 green (check 1 took 35s);
coverage map built to completion: "749 subjects, 908 tests in
coverage map"; run then ended with exit 130 (SIGINT) before any
mutation-phase output. No JSON report produced (score N/A). The
signal origin is not established by the log; no cause claimed.

MEASURED exit=130 wall=295.52s rss_kb=506204 (log footer), matching
reports/map3/measurement.json (raw wrapper; status null,
evidence_paths [] - known limitation, raw immutable, enriched copy
owed by author).

Publisher verification:
- Wrapper envelope 07:31:41.278849 -> 07:36:36.803240 recomputes to
  295.524s = wall_seconds 295.52. No timestamp-vs-wall divergence in
  THIS run (contrast map2: 502.41 vs 1213.27, still OPEN - map3
  agreement does not resolve map2).
- Clock trace (logs/map3-20261024-0732-clock-trace.log, 30s samples):
  monotonic and wall clocks advance in lockstep (360.7s vs 360.6s
  over 07:31:41-07:37:41) - no wall-clock jump during this run.
- Map totals 749 subjects / 908 tests match the map2 build and the
  three green 908/0 pass logs. No "user_administration" string
  anywhere in the packet (grep -c = 0); spec count 908 is consistent
  with EX-1 remaining active.
- The producer's approximate phase split (~80s baselines + ~220s map)
  is an approximation from log progress lines, not a measured sum;
  it is not published as a measurement.

Status: whole-suite map artifact itself completed in-run, but the
mutation phase did not run, so the whole-map CI flow is still NOT
demonstrated end-to-end. All five replay rows remain selected-spec
scope (see reports/QUALIFICATION-selected-specs-20261024.md).
