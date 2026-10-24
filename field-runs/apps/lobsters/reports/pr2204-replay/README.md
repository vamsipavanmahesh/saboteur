# PR 2204 replay (2026-10-24 07:18 IST)

Result: 19/22 mutants killed, 3 survivors, score 86.4%. exit 1
(survivors). MEASURED exit=1 wall=62.65s rss_kb=391532 (saboteur
internal 61.8s; baseline 4.9s, map 24.8s, mutants 21.9s, jobs=1).

- Scope: --since 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76, seed 1,
  --jobs 1, baseline-passes 1, max-duration 10m; 37 default operators.
- Mutated file: app/models/story.rb (subject Story#is_gone?).
- Survivors (all app/models/story.rb:777, Story#is_gone?):
  56ec2857eb8103bd comparison `<` -> `<=` (boundary);
  695982748e0e8ebb literal_number `0` -> `1`;
  9786b8df27eddc21 literal_number `0` -> `(-1)`.
  report.json: 18 assertionKills + 1 crashKill, timeouts=0,
  rejectedKills=0, complete=true, exitCause=survivors, no
  inlineSuppressions, no ignore-file accepted mutants, no earlyStop.
- Identity: saboteur 0.12.3 built from
  6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
  407536444934ac7d78f4ce1c18f228e3891a8663.
- EX-1 active: spec/features/user_administration_spec.rb excluded via
  rspec_args --exclude-pattern (user-approved 06:52). Publisher-side
  fake-kill check on THIS report.json: zero occurrences of
  "user_administration" anywhere in the file (grep -c = 0); the spec is
  also absent from testFiles (spec/models/story_spec.rb only).
- Per-replay structured measurement.json not yet supplied by the worker;
  the raw MEASURED footer is in logs/pr2204-replay-20261024-0718.log.

Update 07:24: wrapper measurement.json received and added (envelope
07:18:28.350769 -> 07:19:31.004332 = 62.65s, agrees with the MEASURED
footer; head_sha ed722e449227b39ab6268f4260aaa66df95275bd).
Qualifications: kills are 18 assertion + 1 crash (tool labels, not
independent verdicts); the 3 survivors are unconfirmed, not yet
real-gap findings; the tool score reflects the selected tests only;
independent triage is ongoing.
