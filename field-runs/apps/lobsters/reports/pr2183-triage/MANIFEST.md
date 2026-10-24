# PR 2183 survivor triage case packet (independent field-run verification)
- PR: lobsters/lobsters #2183 "Rails.cache around a keystore caused query storms"; head 3af3f79a6de5f1437fe8d60236fdee685c67c96b; base (--since) 809f7030fb479e13f53d1aad56c9057fe8b24727
- Era: proofs run 2026-10-24 11:57-11:59 IST on fresh worktree tree-2183 at PR head
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec)
- Packet source: pr2183-ex2.tar-bfe0d018.gz sha256 37ee9b7e3063f1640980fb24b0d27bcf7c36a547d0b215a36cf55e2fc762ee7e; IDs/edits verbatim from its report.json
- Packet run (ex2b corrective, 5 covering controllers after plain run exit 2 = missing traffic_helper_spec): 10 mutants, 5K, 5 survived=UNCONFIRMED, 61.23s. Packet EX2 (CSS lint 14 examples excluded, head/base red) is the packet's own deviation; proofs use only the 5 covering controller specs + probe, no mutated-config assumption.
- Subject: TrafficHelper.cached_current_intensity (traffic_helper.rb:59): Keystore.value_for("traffic:intensity") || 0.5

## Survivors and proofs (all REAL GAP, unit level; whole-existing-suite UNCONFIRMED)
| ID (full, live order) | Operator | Edit | Existing 5 controllers under mutant | Probe kill |
|---|---|---|---|---|
| 0a158cf837a4e9ac | literal_number | 0.5 -> (-0.5) | 34/0 pass (survives) | T2 fails |
| 0e77ab7c5fd1ae29 | boolean_logic | expr -> 0.5 | 34/0 (survives) | T1 fails |
| 6ad124cc7a87c548 | literal_number | 0.5 -> 0.0 | 34/0 (survives) | T2 fails |
| a7b41e60aed29c41 | literal_number | 0.5 -> 1.5 | 34/0 (survives) | T2 fails |
| c8e920b3b0bbbbed | literal_string | "traffic:intensity" -> "" | 34/0 (survives) | T1 fails |

## Grouping (both ways; the study owns the gap unit)
- Per behavior gap: 1 - the intensity fallback value and keystore lookup are unasserted (covering controller specs render pages but never pin the returned intensity)
- Per statement: 1 (traffic_helper.rb:59)
- Per mutant: 5

## Controls
- Probe iteration note: v1 stored fractional 0.77; keystores.value is bigint and type-casts to 0, failing T1 on original. Corrected to integer 7 (v2, attached verbatim); all receipts below are v2.
- Original baseline: 36 examples, 0 failures (5 controllers + T1 + T2)
- Per mutant: existing 5 controller specs 34/0 under mutant (survival reproduced); probe failure exactly as tabled; git checkout revert 0 diff lines
- Restored control: final-restored.log 36/0; probe removed; git status app/ spec/ config/ clean

## Completeness limits
- Unit proofs cover the 5 covering controller specs + probe only; survivors remain NOT existing-whole-suite-confirmed (snapshot pointer covers no edited lines).
- 5 kills not re-gated (no anomaly).
