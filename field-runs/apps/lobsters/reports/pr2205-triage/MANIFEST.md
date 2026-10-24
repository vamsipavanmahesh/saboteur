# PR 2205 survivor triage case packet (independent field-run verification)
- PR: lobsters/lobsters #2205 "use exists? instead of find_by for boolean checks"; head 96f0edec8807f8027af9ca7c1bb973abd2beba55; base (--since) fb4afa937f9ebfce374fef14ec1272a620b06d71
- Era: proofs run 2026-10-24 11:47:42-11:51:12 IST on fresh worktree tree-2205 at PR head
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec, lockfile-pinned)
- Packet source: pr2205-corrective.tar-6fb7aba3.gz sha256 92fae635c16f361e76e55bdc87397684ebb70765def24fba81074753d31d45f8; mutant IDs/edits extracted verbatim from its report.json (incl. two-edit pair_removal spans)
- Packet run: corrective (--test 5 covering specs replacing inference after --since exit 3 line-drift false coverage gap); 10 mutants, 2 crash kills, 8 survived=UNCONFIRMED, 101.2s wall
- Subjects: Story#is_hidden_by_user? (story.rb:781), Story#is_saved_by_user? (story.rb:789)

## Survivors and proofs (all REAL GAP, unit level; whole-existing-suite UNCONFIRMED)
| ID (full) | Subject | Operator | Edit | Existing 5 covering files under mutant | Probe kill |
|---|---|---|---|---|---|
| 030338415f22872f | hidden | body_false | -> false | 46/0 pass (survives) | H1 fails |
| 380d564f2434c995 | hidden | body_true | -> true | 46/0 (survives) | H2,H3,H4 fail |
| f50093f348880e7f | saved | body_true | -> true | 46/0 (survives) | S2,S3,S4 fail |
| f5f54769759d3f8a | saved | body_false | -> false | 46/0 (survives) | S1 fails |
| 48e53f1a3e940cd8 | hidden | pair_removal | exists?(story_id: id) | 46/0 (survives) | H3 fails |
| ce014587c8ab2093 | hidden | pair_removal | exists?(user_id: user.id) | 46/0 (survives) | H4 fails |
| 5988c535eefd7cbd | saved | pair_removal | exists?(story_id: id) | 46/0 (survives) | S3 fails |
| 77cce71ad8c3e450 | saved | pair_removal | exists?(user_id: user.id) | 46/0 (survives) | S4 fails |

(Live order per packet findings.order: 030338415f22872f, 380d564f2434c995, f50093f348880e7f, f5f54769759d3f8a, 48e53f1a3e940cd8, ce014587c8ab2093, 5988c535eefd7cbd, 77cce71ad8c3e450; proof execution order in driver.log.)

## Grouping (reported both ways; the study records the consistent gap unit)
- Per behavior gap: 2 - hidden-state predicate unasserted (4 mutants) / saved-state predicate unasserted (4 mutants). The 5 covering feature/request files exercise these predicates only in ways that pass under every mutation; no test asserts per-user/per-story scoping or positive/negative outcomes.
- Per statement: 2 (story.rb:781 body, story.rb:789 body)
- Per mutant: 8

## Controls
- Original baseline: 54 examples, 0 failures (5 covering files + 8 probe examples)
- Per mutant: applied edit diff shown in driver.log; existing 5 covering files 46 examples 0 failures (survival reproduced on the verification tree); probe failures exactly as tabled; git checkout revert 0 diff lines each
- Restored control: final-restored.log 54 examples, 0 failures; probe removed; git status app/ spec/ config/ clean

## Completeness limits
- Unit proofs cover the 5 covering specs + model probe only; survivors remain NOT existing-whole-suite-confirmed (snapshot pointer covers no edited lines).
- The 2 body_raise kills are crash kills per the packet; not re-gated (no anomaly).
