# PR 2182 replay (2026-10-24 07:24 IST)

Result: 0 mutants - nothing to gate. Score: n/a (nothing tested). exit 0.
MEASURED exit=0 wall=10.73s rss_kb=338344 (saboteur internal 10.13s);
wrapper measurement.json agrees (envelope 07:24:46.325148 ->
07:24:57.059676 = 10.73s).

- The PR's changed lines (app/models/story.rb) carry no mutation
  subject: saboteur reports "no changed file has a mutation subject on
  its changed lines (layout-only edits, deletions, or intentionally
  untested code)". This is NOT a 100% score and NOT a nonzero run.
- Scope: --since e5fda5974779549267ac25fdf4855fdd0cf0101b (base), PR
  merge tree afd505e45084f7c9fd504ae8968886eee102c961, seed 1, --jobs 1,
  baseline-passes 1, max-duration 10m.
- report.json (schemaVersion 2): files={}, testFiles={}, tested=0,
  score=null, complete=true, exitCause=ok, timeouts=0, rejectedKills=0.
- Identity: saboteur 0.12.3 built from
  6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
  407536444934ac7d78f4ce1c18f228e3891a8663.
- EX-1 active: spec/features/user_administration_spec.rb excluded via
  rspec_args --exclude-pattern (user-approved 06:52). Publisher-side
  fake-kill check on THIS report.json: zero occurrences of
  "user_administration" (grep -c = 0); testFiles is empty.
- Wrapper measurement published raw (status null / empty evidence_paths
  in the source record).
