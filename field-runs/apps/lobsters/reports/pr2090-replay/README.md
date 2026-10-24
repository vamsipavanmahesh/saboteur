# PR 2090 replay (2026-10-24 07:23 IST)

Result: 7/7 mutants killed, 0 survivors, score 100.0%. exit 0.
MEASURED exit=0 wall=45.9s rss_kb=407052 (saboteur internal 45.3s);
wrapper measurement.json agrees (envelope 07:23:27.352592 ->
07:24:13.249739 = 45.90s).

- Scope: --since 81ba649e1a667afddd1c780d0aeb37bad37ac308 (base), PR
  merge tree 87e1e318fc7cc914646605c34dae39ff4d28ef34, seed 1, --jobs 1,
  baseline-passes 1, max-duration 10m; 37 default operators.
- Mutated file: app/controllers/home_controller.rb.
- report.json (schemaVersion 2): complete=true, exitCause=ok,
  timeouts=0, rejectedKills=0; 6 assertionKills + 1 crashKill;
  no inlineSuppressions, no ignore-file accepted mutants, no earlyStop.
- Identity: saboteur 0.12.3 built from
  6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
  407536444934ac7d78f4ce1c18f228e3891a8663.
- EX-1 active: spec/features/user_administration_spec.rb excluded via
  rspec_args --exclude-pattern (user-approved 06:52). Publisher-side
  fake-kill check on THIS report.json: zero occurrences of
  "user_administration" anywhere in the file (grep -c = 0); the spec is
  also absent from testFiles (spec/controllers/home_controller_spec.rb
  only).
- Kill-cause caveat: tool score reflects the selected tests only; kill
  causes (assertion vs crash) are tool labels, not independent verdicts;
  independent triage is ongoing. Wrapper measurement published raw
  (status null / empty evidence_paths in the source record).
