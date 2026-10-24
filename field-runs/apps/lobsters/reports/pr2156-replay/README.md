# PR 2156 replay (2026-10-24 07:21 IST)

Result: 6/7 mutants killed, 1 survivor, score 85.7%. exit 1 (survivor).
MEASURED exit=1 wall=25.54s rss_kb=353436; wrapper measurement.json
agrees (envelope 07:21:48.345018 -> 07:22:13.884942 = 25.54s).

- Scope: --since 9a773eac0b49fd86b16585ad503de9a51919c496 (base), PR
  merge tree d9998c2555317db7b3cb9a159ef7878ff993ab78, seed 1, --jobs 1,
  baseline-passes 1, max-duration 10m; 37 default operators.
- Mutated file: app/controllers/settings_controller.rb
  (SettingsController#update).
- Survivor: 84a2b3ca16355339, condition_true at
  settings_controller.rb:51 (`@edit_user.username_previously_changed?`
  -> `true`). Unconfirmed; not yet a real-gap finding (triage pending).
- report.json (schemaVersion 2): complete=true, exitCause=survivors,
  timeouts=0, rejectedKills=0; 4 assertionKills + 2 crashKills;
  no inlineSuppressions, no ignore-file accepted mutants, no earlyStop.
- Identity: saboteur 0.12.3 built from
  6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, lobsters
  407536444934ac7d78f4ce1c18f228e3891a8663.
- EX-1 active: spec/features/user_administration_spec.rb excluded via
  rspec_args --exclude-pattern (user-approved 06:52). Publisher-side
  fake-kill check on THIS report.json: zero occurrences of
  "user_administration" anywhere in the file (grep -c = 0); the spec is
  also absent from testFiles (spec/controllers/settings_controller_spec.rb
  only).
- Kill-cause caveat: tool score reflects the selected tests only; kill
  causes (assertion vs crash) are tool labels, not independent verdicts;
  independent triage is ongoing.
