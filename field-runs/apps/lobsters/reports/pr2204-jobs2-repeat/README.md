# PR 2204 --jobs 2 instrumented repeat (2026-10-24 07:29 IST)

Result: 19/22 killed, 3 survivors, score 86.4%. exit 1. MEASURED
exit=1 wall=32.49s rss_kb=392576 (log footer; coverage map cached,
81 tests). Wrapper measurement.jobs2-repeat.json arrived in the 07:32
bundle and matches the log footer exactly (wall 32.49s, rss 392576,
exit 1); envelope span recomputes to the same wall time. Wrapper
status remains null / evidence_paths [] (known limitation; raw kept
immutable).

- Publisher-side diff: this report.json is IDENTICAL to both the jobs-2
  original and the serial replay on id/status/killedBy (exact values,
  22 mutants).
- DB observation: db-separation-trace.md arrived in the 07:32 bundle.
  It is a PRODUCER-WRITTEN observation narrative (3s ls polling during
  this run), NOT a raw poll transcript: per-worker copies
  primary/cache/queue/rack_attack_saboteur2.sqlite3 present at the
  07:29:48 poll, dropped post-run. The poll events remain
  worker-reported; a raw poll transcript is still owed. Publisher
  verified only the source mechanism at the pin (rails.rb
  worker_database() names <db>_saboteur<N>.<ext>, prepare_workers
  copies for jobs>1, cleanup_workers drops after the run) and the
  trace's internal timeline consistency with the wrapper envelope.
  DB isolation is NOT claimed as independently proven; the 22/22
  zero-diff parity remains a verdict fact only, not evidence of
  isolated or safe DB sharing.
- Fake-kill: zero "user_administration" occurrences (grep -c = 0);
  testFiles = spec/models/story_spec.rb only; rejectedKills=0;
  timeouts=0. EX-1 active (user-approved 06:52).
- CI-flow qualification: this evidence is SELECTED-SPEC scope, not
  the requested whole-map CI flow; see
  reports/QUALIFICATION-selected-specs-20261024.md.
- Identity: saboteur 0.12.3 @ 6f87ccc98377bf0c23f3cf409006f0464c2aa67c,
  Ruby 4.0.0, lobsters 407536444934ac7d78f4ce1c18f228e3891a8663.
