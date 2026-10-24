# PR 2103 CORRECTIVE2 survivor triage case packet (independent field-run verification)
- PR: lobsters/lobsters #2103 "Refactor header section"; head a11fe0c52269ddac2ec36641aebe69ce74ecae0b; base (--since) 1c22c1e326fa3b5e094844519f6df867dd33198a
- Corrective2 packet: pr2103-corrective2.tar-9f390960.gz sha256 e77cf43acf05870aefc55bb7ba4cdf7b424432a85779d4164f444850b5873a4f (supersedes pr2103-row-d54; helper + 5 controllers union via --test, replacing inference)
- Packet run: 19 mutants / 2 subjects: 5 killed, 6 survived=UNCONFIRMED, 8 NoCoverage, 55.33s wall
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec)
- Covering set (packet --test): spec/helpers/application_helper_spec.rb + spec/controllers/{comments,home,inbox,messages,story_image}_controller_spec.rb

## Survivor ledger (6, live order) - all REAL GAP unit-proved; whole-existing-suite UNCONFIRMED
| ID (full) | Subject | Operator | Edit | Proof |
|---|---|---|---|---|
| 3357bbd3579ca0dc | link_to_different_page:109 | condition_negation | cond -> !(cond) | REUSED from packet-2103.tar.gz (exact ID+edit match vs corrective2 report) |
| 97154a11ddda03c6 | link_to_different_page:109 | condition_true | cond -> true | REUSED (match verified) |
| b108a3614e6b02a4 | link_to_different_page:109 | condition_false | cond -> false | REUSED (match verified) |
| 629ab82786f06cb3 | link_to_different_page:108 | argument_removal | class_names arg removed | REUSED (match verified) |
| 556caf228d63258a | TrafficHelper.novelty_logo:63-101 | body_nil | body -> nil | NEW this packet |
| 2da30124e7509574 | TrafficHelper.novelty_logo:66-99 | statement_removal | if/elsif chain removed | NEW this packet |

Reuse verification: corrective2 report's line/original/replacement for the 4 link_to_different_page survivors are byte-identical to the d54 report's edits proved in packet-2103.tar.gz (sha256 4e472546ccb3e2d1b220f46bf81053ed1b338f4f13f5ce2cd9ec012f58ed8ddb).

## New proofs (novelty_logo, era 2026-10-24 11:52-11:53 IST, tree-2103 at PR head)
- Both mutants make novelty_logo always nil; the 28 covering tests run at real time (October) when no logo renders, so output is never asserted.
- Probe (temporary helper-spec specimen, travel_to; removed after): N1 = Casimir Pulaski logo present on 2026-03-02 (verified Monday via DIAG line); N2 = nil on ordinary day (sanity, passes under both).
- 556caf228d63258a: existing 6 covering files 52/0 under mutant (survival reproduced); probe N1 fails (kill), N2 passes; revert 0 diff.
- 2da30124e7509574: existing 52/0; probe N1 fails (kill), N2 passes; revert 0 diff.
- Controls: baseline 54/0 (6 files + probe); final restored 54/0; tree clean (app/ spec/ config/).

## Grouping (both ways; the study owns the gap unit)
- Per behavior gap: 2 - (a) unasserted empty-class handling in link_to_different_page (4 mutants), (b) unasserted novelty_logo seasonal output (2 mutants, behaviorally identical always-nil).
- Per statement/span: 3 - application_helper.rb:108, application_helper.rb:109, traffic_helper.rb method body (spans 63-101 / 66-99 overlap; counted once).
- Per mutant: 6.
- NoCoverage 8 (traffic_helper.rb:67-71 literal_string x3, pair_removal x4, jump_value x1): NOT classified as survivors and NOT as real gaps; the corrective run's covering set did not execute those lines. No no-coverage-equals-no-tests claim.

## Completeness limits
- Unit proofs cover the corrective2 covering set only; all 6 survivors remain NOT existing-whole-suite-confirmed (snapshot pointer covers no edited lines; line shift noted by the publication review).
- 5 kills (4 link_to_different_page incl. 1 assertion + body_nil/body_raise/statement_removal/argument_removal crash class per d54 packet; 1 novelty_logo body_raise crash) not re-gated, no anomaly.
