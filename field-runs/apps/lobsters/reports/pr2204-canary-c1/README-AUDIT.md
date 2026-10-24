# Known-survivor canary PR 2204 (c1) - merger audit: SURVIVOR-CONFIRMATION MECHANISM PROVEN (2026-10-24 09:46 IST)

Raw canary packet (R-side report.json + run log + whole-suite-map-v2 pointer file). M-side receipts (map coverage file, 747-subject/861-test count, owned fresh boundary exit 130) are asserted by the worker and NOT in this packet; they gate the 2204 ROW, not this protocol verdict.

## Protocol verdict: the whole-suite map's role in scoped runs is now proven end-to-end from raws
- R ran scoped (inference: "running only spec/models/story_spec.rb", 81-test scoped map, settings-miss note as designed per D36). 22 mutants: 19 killed (18 assertion + 1 crash), 3 survived, 0 rejected kills, complete=true, exitCause=survivors, exit 1.
- The 3 survivors (56ec2857eb8103bd comparison <-><=; 695982748e0e8ebb literal 1; 9786b8df27eddc21 literal -1; all app/models/story.rb:777) carry confirmation="confirmed" with coveredBy arrays resolved through the report's testFiles: 19 story_spec examples PLUS whole-suite knowledge that search_spec covers line 777. search_spec was NOT in the inferred selection and CANNOT be in the 81-test scoped map - it appears in the executed set (27 tests incl. search_spec[1:1], [1:12], [1:16], [1:19], [1:32:1]) solely because survivor confirmation read M's whole-suite map (pointer c091018a963bc80c9d388f788d94d79879624351d483c728f7481d0a86905b2c, attached) and ran the covering specs. Raw log receipt per survivor: "confirmed: ./spec/models/search_spec.rb[1:1] ran on confirmation and still passed".
- This closes the D38 gate: the survivor-confirmation path (#1063) and whole-suite presentation (C1) are no longer unproven. Vacuous-at-zero-survivors no longer applies; the mechanism engaged, ran real specs from outside the selection, and produced verdicts.

## Base independence (merger's own API check, not the ledger)
PR 2204 merge commit ed722e449227b39ab6268f4260aaa66df95275bd (single-parent squash merge); its sole parent is 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 - the R run's --since base is exactly the merge's main-line parent. Verified via the GitHub API at 09:46 IST (the PR record's base.sha 57268d76 is the base-branch field, NOT the merge parent, and was correctly not used).

## Classification boundaries (kept distinct, no forced agreement)
- These 3 mutants are NOISE-STUDY candidates (historical fix PR in the noise window), triage open (equivalent vs real gap; the report itself notes the line-777 boundary is untested). They are NOT missed-bug HIT candidates: the bug study requires an eligible INTRODUCER replay and PR 2204's introducing PR is skipped under the user's B2 rule (different DB - MariaDB).
- The verifier's earlier inclusive whole-suite run had the SAME 3 IDs as rejected kills (killers failed on unchanged code, Domain-collision pollution) = UNRESOLVED in that protocol scope; this canary run (fresh state, different ordering) shows no pollution and confirms them as survivors. Both facts stand in their own scopes; no agreement is forced between them.
- The 19 kills' cause verification is a separate ongoing gate (fresh-seed reruns); it does not block this protocol verdict, exactly as in the 2231 row.
