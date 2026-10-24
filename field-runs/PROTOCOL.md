# Whole-suite map protocol for replays (source-grounded at saboteur 0.12.3, commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c)

Decision: 2026-10-24 08:46 IST. Defines the supported route every replay row must use. All mechanism claims below were verified against the pinned source; the user's request is "run with the whole-suite map" and "saboteur pr on the introducing PR (base = its parent) with the tests as they existed then".

## The route (the documented two-job design, docs/ci-whole-suite-map.md)

1. MAP JOB, once per era tree: an unscoped whole-suite build (`saboteur run --all`, no --since/--test/--subject, cache on, one coverage part). It writes three artifacts under the cache dir: the coverage map, the inputs snapshot, and the whole-suite-map-v2 pointer. A map without the pointer is never read as a whole-suite map, so survivors stay unconfirmed rather than confirmed against the wrong thing.
2. REPLAY JOB: `saboteur run --since <base>` (the pr preset) with `partial_coverage = "use"`, in the SAME working directory (same realpath), with an identical configuration file. It restores or rebuilds the map as follows and confirms each survivor against the pointer-named whole-suite map.

## Why the pointer matters

Survivor confirmation (#1286) uses only the pointer-named whole-suite map, never the run's own selection map (engine.rb:299-311). The pointer is written only by an unscoped whole-suite run (engine.rb:390-392). A `--since` replay never writes it. Without a prior map job in the same cache dir, every survivor stays unconfirmed.

## Restore semantics, verified at the pin

- Exact cache HIT requires identical tree and settings: the key hashes the settings JSON plus the content digests of every included source file, spec file and lockfile (selection/coverage_map.rb:302-309). A cross-tree exact hit is impossible by design; a stale map served across trees would be wrong, so this is correctness, not a limitation to work around.
- PARTIAL reuse (engine/coverage_partial.rb, #46): after a miss, the latest inputs snapshot in the same cache dir is used as the base. Preconditions: `partial_coverage == "use"`, cache on, no explicit `--test` (inferred specs do not count; inference never writes the tests setting, selection_announcement.rb:62), one coverage part. The snapshot's format, root, runtime and settings digests must all match (partial_invalidation.rb:24,45). Only two kinds of changed file take the partial path: suite spec files, and included source files with recorded coverage evidence that did not run at load. Any added or removed file, fixture, template or config change forces FULL, as does a stale-spec share above 50% of recorded spec time. Stale specs are rerun and merged; the result is a current-tree map with the recorded provenance.
- FULL fallback: an honest whole-suite map built on the current tree. It is never described as consuming an earlier map.
- Ordering hazard: the partial path trusts the newest snapshot in the cache dir. No scoped run may write to that cache dir between the map job and the replay.

## Honest row labels

Each replay row records one of:
- "cache hit on whole-suite map <key> (built at <tree>)"
- "partial-merged from whole-suite map <key> seeded at <tree>, N of M spec files rerun"
- "full map build at <tree> (partial fallback: <reason>)"
Survivor confirmation is recorded as "confirmed against pointer whole-suite map built at <tree>", or the survivors are reported unconfirmed.

## Canary (PR 2231) before any noise-row execution

1. Fixed root path (recorded); clean checkout at the PR 2231 merge commit 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8; config file sha256, Ruby version and saboteur pin recorded.
2. Run M (map job): `saboteur run --all --max-duration 10m`. Expect a whole-suite map build (~882 tests for lobsters) and all three artifacts. A budget stop during mutation is acceptable: the map and pointer persist before mutation begins.
3. Run R (replay): same root and tree, `saboteur run --since 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c` with `partial_coverage = "use"`. Expect an exact cache hit, ~882 map tests, and survivor confirmation active. A completed run is the qualified row for PR 2231.
4. Optional run R2: checkout the next era tree in the same root and replay its PR; observe PARTIAL or FULL verbatim. This proves the cross-tree route for the remaining rows.
5. Raw provenance published per run: the exact cache line, map test count, pointer presence, exit code, wall seconds, clean-tree `git status`, exact command and config sha256.

## Failure of the earlier attempts

The 2231 v2 replay ran in a different root than its base build, with different settings digests, on a dirty working tree (186 uncommitted/untracked changes), and built a 44-test inferred-spec map on a cache miss. The 2204/2156 v2 replays reused 81/1-test selected-spec maps. All three rows are provisional selected-spec work, not whole-suite rows, until re-run under this protocol.
