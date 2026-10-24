# PR 2204 --jobs 2 instrumented repeat (2026-10-24 07:29 IST)

Result: 19/22 killed, 3 survivors, score 86.4%. exit 1. MEASURED
exit=1 wall=32.49s rss_kb=392576 (log footer; coverage map cached,
81 tests). No wrapper measurement.json in this packet - forthcoming.

- Publisher-side diff: this report.json is IDENTICAL to both the jobs-2
  original and the serial replay on id/status/killedBy (exact values,
  22 mutants).
- Worker-reported DB observation during this instrumented repeat:
  db/test held primary/cache/queue/rack_attack_saboteur2 SQLite copies
  plus worker1 originals, with cleanup dropped post-run. The mechanism
  is consistent with the expected rails.rb setup but the actual
  connection trace attachment is still forthcoming - DB isolation is
  NOT claimed as proven; the 22/22 zero-diff parity remains a verdict
  fact only, not evidence of isolated or safe DB sharing.
- Fake-kill: zero "user_administration" occurrences (grep -c = 0);
  testFiles = spec/models/story_spec.rb only; rejectedKills=0;
  timeouts=0. EX-1 active (user-approved 06:52).
- Identity: saboteur 0.12.3 @ 6f87ccc98377bf0c23f3cf409006f0464c2aa67c,
  Ruby 4.0.0, lobsters 407536444934ac7d78f4ce1c18f228e3891a8663.
