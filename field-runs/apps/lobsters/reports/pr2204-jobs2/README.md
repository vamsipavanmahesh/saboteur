# PR 2204 replay, --jobs 2 parity run (2026-10-24 07:26 IST)

Result: 19/22 killed, 3 survivors, score 86.4%. exit 1 (survivors).
MEASURED exit=1 wall=31.72s rss_kb=377876 (serial was 62.65s); wrapper
envelope 07:26:07.200621 -> 07:26:38.920319 = 31.72s agrees.

- Same scope as the serial replay: --since
  8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 (base), merge tree
  ed722e449227b39ab6268f4260aaa66df95275bd, seed 1, --jobs 2.
- Verdict parity: publisher-side independent diff of this report.json
  against the serial report.json: identical 22 mutant IDs, ZERO
  differences in status, killedBy or kill reason for every mutant;
  same score composition (18 assertion + 1 crash kills, same 3
  survivors). The author's verdict-diff.json records "IDENTICAL".
- Fake-kill: zero "user_administration" occurrences (grep -c = 0);
  testFiles = spec/models/story_spec.rb only; every killed mutant's
  killedBy resolves; rejectedKills=0; timeouts=0.
- Identity: saboteur 0.12.3 @ 6f87ccc98377bf0c23f3cf409006f0464c2aa67c,
  Ruby 4.0.0, lobsters 407536444934ac7d78f4ce1c18f228e3891a8663; EX-1
  active (user-approved 06:52).

## Limits of this evidence

- ONE serial/jobs-2 pair on ONE PR: not a general 2x-speedup or
  parallelism verdict.
- Per-worker database isolation is NOT proven: only the config contract
  (rails=true) is recorded; no actual per-worker DB trace exists yet.
  Zero verdict diff does NOT prove absence of cross-contamination.
  The per-worker-DB requirement is PARTIAL pending the worker's trace.
- Wrapper measurement published raw (status null / empty evidence_paths
  in the source record).

Producer follow-up (07:27): after the jobs-2 run, db/test contained only
the primary/cache/queue SQLite files - no worker-suffixed DB files. The
per-worker DB mechanism is therefore unknown (the config comment did not
manifest as visible files). DB isolation remains UNPROVEN; do not read
the 22/22 zero-diff parity as evidence of isolated or safe sharing. A
worker connection trace / code inspection is pending.
