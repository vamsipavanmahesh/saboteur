# PR 2103 survivor triage case packet (verifier: independent field-run verification lane)
- PR: lobsters/lobsters #2103 "Refactor header section"; head a11fe0c52269ddac2ec36641aebe69ce74ecae0b; base (--since) 1c22c1e326fa3b5e094844519f6df867dd33198a
- Era: proofs run 2026-10-24 11:39-11:41 IST on fresh worktree tree-2103 at PR head
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec, lockfile-pinned)
- Packet source: pr2103-row-d54.tar-212be11e.gz sha256 0c1c7b46652b3402b382e7a94ce5c58434fa98159d5591b11b07c37f758dbeb0; mutant IDs/edits extracted verbatim from its report.json (no reconstruction)
- Packet run: 8 mutants, 4 killed (1 assertion + 3 crash), 4 survived=UNCONFIRMED, 27.25s wall, exit 1 (survivors)
- Subject: ApplicationHelper#link_to_different_page (app/helpers/application_helper.rb:105-115)

## Survivors and proofs (all REAL GAP, unit level; whole-existing-suite UNCONFIRMED)
| ID (full) | Line | Operator | Edit | Existing tests under mutant | Probe kill |
|---|---|---|---|---|---|
| 3357bbd3579ca0dc | 109 | condition_negation | cond -> !(cond) | 3/0 pass (survives) | A1+A2 fail |
| 97154a11ddda03c6 | 109 | condition_true | cond -> true | 3/0 pass (survives) | A1 fails |
| b108a3614e6b02a4 | 109 | condition_false | cond -> false | 3/0 pass (survives) | A2 fails |
| 629ab82786f06cb3 | 108 | argument_removal | class_names(options[:class]) -> class_names() | 3/0 pass (survives) | A1 fails |

## Grouping (reported both ways; merger owns the consistent gap unit)
- Per behavior gap: 1 - "empty-class handling of link_to_different_page is unasserted" (no covering test passes or asserts a class attribute; both branch directions and the class_names normalization unobserved)
- Per statement: 2 - line 108 statement (class_names normalization) + line 109 branch (empty-class delete)
- Per mutant: 4

## Controls
- Original baseline: 20 examples, 0 failures (twice; baseline.log, proof-part1/2.log)
- Per-mutant: existing 3 link_to_different_page tests pass 3/0 under mutant (survival reproduced), probe fails as tabled (kill), git checkout revert 0 diff lines
- Restored control: final-restored.log 20 examples, 0 failures; probe spec removed; git status app/ spec/ config/ clean
- Probe spec: ltdp_probe_spec.rb (verbatim copy; temporary specimen, deleted from tree after proofs)

## Files
- baseline.log, final-restored.log, proof-part1.log, proof-part2.log (step transcripts with applied diffs)
- mut-<id>-existing.log / mut-<id>-probe.log per mutant (raw rspec output)
- ltdp_probe_spec.rb (probe source)

## Completeness limits
- Unit proofs cover the covering/loaded specs only; survivors remain NOT existing-whole-suite-confirmed (scoped --since run; snapshot pointer covers no edited lines; 177 snapshot tests cover new lines but line shift leaves pointer unconfirmed).
- TrafficHelper.novelty_logo skip = line-drift per corrected snapshot LINE table (body 62-63 executed by 28 snapshot tests); not a coverage gap; no no-coverage claim made.
- Kills not re-gated (no anomaly).
