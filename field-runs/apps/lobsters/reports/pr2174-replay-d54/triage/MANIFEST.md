# PR 2174 survivor triage case packet (verifier: independent field-run verification lane)
- PR: lobsters/lobsters #2174 "#2166 SQLite migration quietly broke flagged_commenters calculation"; head f04ab91317e8e8999131d0aa7e20e2ce54af1fb2; base (--since) 8b1a34353f00a1fd54f4857cbedb9c2ce7ec837a
- Era: proofs run 2026-10-24 11:44-11:45 IST on fresh worktree tree-2174 at PR head
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec, lockfile-pinned)
- Packet source: pr2174-row-d54.tar-9e460c05.gz sha256 4ffa687172ee7247824503436c40d01d796df04c2b00a1524a980598e4629708; mutant IDs/edits extracted verbatim from its report.json
- Packet run: 7 mutants, 6 killed (all crash), 1 survived=UNCONFIRMED, 33.78s wall, exit 1 (survivors)
- Subject: FlaggedCommenters#commenters (app/models/flagged_commenters.rb:56-...); covering spec in packet map: spec/requests/users_controller_spec.rb

## Survivor and proof (REAL GAP, unit level; whole-existing-suite UNCONFIRMED)
| ID (full) | Line | Operator | Edit | Existing tests under mutant | Probe kill |
|---|---|---|---|---|---|
| de7560d08996f4ef | 72 | chain_removal | remove .having("n_comments > 4 and n_stories > 1 and n_flags >= 10 and percent_flagged > 10") | 12/0 pass (survives) | F1 fails (F2 passes, sanity) |

## Grouping: 1 behavior gap (HAVING-threshold filtering of flagged commenters unasserted) = 1 statement = 1 mutant

## Controls
- Original baseline: 14 examples, 0 failures (12 existing users_controller_spec + F1 + F2)
- Mutant: existing 12/0 (survival reproduced); probe F1 fails -> below-threshold user listed when .having removed (kill); F2 passes
- Restored control: final-restored.log 14/0; probe removed; git status app/ spec/ config/ clean
- Probe spec: fc_probe_spec.rb (verbatim copy; temporary specimen, deleted after proofs)
- Fixture note: comment factory recomputes flags from votes (create-time flags reload as 0, verified by diagnostic); probe sets flags via update_column
- View path: users#show Moderator Information block calls FlaggedCommenters directly as moderator viewer; the env-guarded dev_flag_warning partial is a separate helper path and did not gate this one

## Completeness limits
- Unit proof covers the covering request spec only; survivor remains NOT existing-whole-suite-confirmed (scoped run; snapshot pointer covers no edited lines).
- The 6 kills are all crash kills per the packet; not re-gated (no anomaly).
