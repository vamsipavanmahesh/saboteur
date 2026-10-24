# PR 2156 inclusive all-tests run (lobsters) - merger audit: QUALIFIED PARTIAL, survivor UNCONFIRMED (2026-10-24 09:49 IST)

Verifier-lane raw packet. Verified from raws: command `timeout 3000 bundle exec saboteur run --config config/saboteur-inclusive.rb --since 9a773eac0b49fd86b16585ad503de9a51919c496 --all --jobs 1 --baseline-passes 1 --max-duration 3600 --seed 1` (log line 1). 7 mutants on SettingsController#update (app/controllers/settings_controller.rb): 6 killed (4 assertion + 2 crash), 1 survived, 0 rejected kills, complete=true, exitCause=survivors. Whole existing suite: 865 examples in 105 spec files, no EX-1 (user_administration green on this HEAD).

CRITICAL SEMANTIC (supersedes any "whole-suite confirmed" reading): `--since X --all` runs ALL TESTS but writes NO whole-suite-map-v2 pointer - the tool's own log says "survivors unconfirmed: no whole-suite coverage map" and "covering list is this run's selection only". The survivor 84a2b3ca16355339 (condition_true -> true, line 51; coveredBy/executed = only this run's 2 selected tests) is an UNCONFIRMED survivor candidate. It must not be labeled whole-confirmed until a pointer-bearing bridge run or per-ID confirmation proof lands. The producer's 2204-c1 mechanism proof (pointer present, confirmation engaged) stands separately and is unaffected.

Base independently API-verified (merger, 09:49 IST): PR 2156 merge d9998c2555317db7b3cb9a159ef7878ff993ab78 (single-parent squash); sole parent 9a773eac0b49fd86b16585ad503de9a51919c496 == the --since base.

Specimen original-PASS halves (verifier's independent-verification specs, original code): 2156 settings_no_rename 1 example 0 failures exit 0; 2204 is_gone boundary 2 examples 0 failures exit 0. Mutant-FAIL halves and 14 remaining fresh reruns are in flight; kill-cause gates for the 6 kills stay open until they land.

Runtime caveat (standing): verifier lane executes pinned SOURCE via path gem (6f87ccc9, content byte-identical to the built artifact per merger audit), NOT the vendored artifact - do not claim artifact execution for this lane. Lock proof: additions-only, see field-runs/tool-verification/2026-10-24-verifier-lock-receipt.txt.
