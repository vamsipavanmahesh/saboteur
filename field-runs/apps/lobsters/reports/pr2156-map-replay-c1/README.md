# PR 2156 map+replay attempt c1 (lobsters) - merger audit: QUALIFIED WITH DISCLOSED DEVIATION (lock receipt pending) (2026-10-24 10:24 IST)

Producer packet verified from raws:

MAP (c1): runner headmap2.sh sha256=255d0ae9e5523370e8bc85d85b25af3a7ab3424bc04de8b02089ffa246f8888b, tree pr2156 at d9998c2555317db7b3cb9a159ef7878ff993ab78 (merger API-verified merge SHA), 865 examples/105 files, 738 subjects/865 tests, MEASURED exit=130 wall=787.83s = boundary stop after map build (observer freshness-verified, owned PGID 26861/PID 26871), key 8d81ef14431f4640fe31e3ea9da20eea2247a791e02ccaebbf086c2c04ec7957. Binding chain merger-verified: pointer == inputs.map_key == key; inputs.map_digest == actual coverage sha256; 865 tests in coverage.

REPLAY (c1r): --since 9a773eac0b49fd86b16585ad503de9a51919c496 (merger API-verified sole parent of the merge). 7 mutants on SettingsController#update: 6 killed (4 assertion + 2 crash: RuntimeError 1 + ArgumentError 1; operators body_raise, pair_removal) + 1 survived, 0 rejected, exit 1, MEASURED wall=23.65s. Kill IDs == the verifier frozen-pool 2156 kills exactly (5e66e0c9f4a67ce7, a1b1a8ee35850a2f, 2d9c4a7071cf07be, 5a3f2be4c6cfdd28, 978f3620488546a9, 8afbb58fbb832398).

BRIDGE ACTUAL (not assumed): stdout "confirmation: 1 confirmed"; survivor 84a2b3ca16355339 (condition_true -> true, line 51) confirmed via ./spec/requests/settings_spec.rb[1:1:1] - a file NOT in the inferred 1-file selection (settings_controller_spec.rb), i.e. the whole-map pointer contributed it; it ran on confirmation and still passed. The survivor is existing-suite-confirmed.

SURVIVOR TRIAGE: REAL GAP - independently proven by the verifier (packet 2a): original-code PASS (1 example 0 failures) + new-spec assertion KILL (zz_independent_verification_settings_no_rename_spec.rb[1:1:1]) on the same full ID.

ROW RESULT: 7 mutants = 6K + 1 confirmed S (REAL GAP). Noise = 0/1 = 0% descriptive. Top finding = 84a2b3ca16355339 REAL GAP. No interval (PR-cluster <2; app interval at the 15-row block).

DEVIATION (disclosed): the PRODUCER's 2156 tree lock is unreceipted (headmap2 preamble gap, same class as pre-gapfix 2157). The metric-bearing survivor classification is bump-free (verifier lane, additions-only 4-tree receipt, independent reproduction of survivor proof + one kill); the producer kill set carries the unreceipted-environment caveat. UPGRADE PATH to strict: producer backfills the 2156 bounded lock diff (same posthoc-with-hashes shape as the 2157 gapfix). The verifier-lane original inclusive 865-test run (published pr2156-confirm-all-inclusive) remains a coverage-complete scoped supplement with no pointer semantics.
