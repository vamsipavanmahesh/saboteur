# PR 2174 row audit (merger, 2026-10-24)

Exit 1, 7 mutants = 6 killed (all crash) + 1 survivor, wall 33.78s, no skips. Snapshot copy hashes verified. Survivor UNCONFIRMED - row QUALIFIED after independent triage (case packet in triage/): 1 behavior gap (1 statement, 1 mutant): .having threshold filtering of flagged commenters unasserted; survivor probe-killed (real gap, unit level). Whole-existing-suite confirmation remains UNCONFIRMED by contract; controls baseline/restored clean, source-tar hashes verified against MANIFEST.

Survivor: de7560d08996f4ef app/models/flagged_commenters.rb:72 chain_removal on the .having(...) threshold chain, subject FlaggedCommenters#commenters. Suggested replay spec: spec/requests/users_controller_spec.rb.
