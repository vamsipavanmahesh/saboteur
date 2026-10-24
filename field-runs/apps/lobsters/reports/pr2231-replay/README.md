# PR 2231 replay (2026-10-24 07:16 IST)

Result: 4/4 mutants killed, 0 survivors, score 100.0%. exit 0.
MEASURED exit=0 wall=35.85s rss_kb=433048 (saboteur internal 35.4s;
baseline 4.0s, map 16.6s, mutants 5.2s, jobs=1). Clock wrapper internal
vs measured wall within 1s on this run.

- Scope: --since 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c, seed 1,
  --jobs 1, baseline-passes 1, max-duration 10m; 37 default operators.
- Mutated file: app/models/comment.rb (subject Comment#parents).
- report.json (schemaVersion 2): complete=true, exitCause=ok,
  timeouts=0, rejectedKills=0, survivors=0 (4 crashKills), no
  inlineSuppressions, no ignore-file accepted mutants, no earlyStop.
- Identity: saboteur 0.12.3 built from
  6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
  407536444934ac7d78f4ce1c18f228e3891a8663.
- EX-1 active: spec/features/user_administration_spec.rb excluded via
  rspec_args --exclude-pattern (user-approved 06:52). Publisher-side
  fake-kill check on THIS report.json: zero occurrences of
  "user_administration" anywhere in the file (grep -c = 0); the spec is
  also absent from testFiles (spec/mailers/email_reply_mailer_spec.rb,
  spec/models/comment_spec.rb, spec/requests/comments_spec.rb only).
- Per-replay structured measurement.json not yet supplied by the worker;
  the raw MEASURED footer is in logs/pr2231-replay-20261024-0716.log.

Update 07:24: wrapper measurement.json received and added (envelope
07:16:38.757915 -> 07:17:14.610503 = 35.85s, agrees with the MEASURED
footer; head_sha 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8).
Qualifications: all 4 kills are tool-labeled crashes, not assertion
kills; the tool score reflects the selected tests only; kill causes are
tool labels, not independent verdicts; independent triage is ongoing.
The earlier setup attempt failed exit 3 / 6.13s (missing database.yml);
the rerun used a copied pin configuration - an explicit deviation whose
source/hash record is tracked in the run notes.
