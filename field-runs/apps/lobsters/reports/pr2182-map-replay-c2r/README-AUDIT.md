# PR 2182 row (snapshot-reuse protocol, D54) - independent audit: STRICT-QUALIFIED, zero-mutant row (2026-10-24 11:33 IST)

First row under the snapshot-reuse flow. Result: 0 subjects, 0 mutants, score N/A, exit 0, wall 11.42s (R only; snapshot map cost amortized at the 2171 row, not here). Noise 0/0 UNDEFINED per the metric contract. Zero-mutant is recorded as zero-mutant - NOT coverage success.

VERIFIED INDEPENDENTLY:
- Snapshot fidelity: the row's copied coverage-975e4b71e35bdae529738d845b23b38450e35d95d24e78273b7eb8e20d4d7c4a.json hashes c379bc360824042abf1d9ee8f32a6ed1ac78b90ed89f34c59edf08074a89b006 - byte-identical to the merger's own published 2171 coverage JSON (own sha256, not the worker's claim). Inputs snapshot + whole-suite-map-v2 pointer present (copy receipt in snapshot-copy-hashes.txt).
- --since e5fda5974779549267ac25fdf4855fdd0cf0101b == the sole parent of 2182's merge afd505e45084f7c9fd504ae8968886eee102c961 (API-verified).
- Settings 240ea092 (no EX-1 active); bounded lock 6b3775bd (same as snapshot window, D54 eligibility).
- Tool output: "no spec is required for app/models/story.rb: it has no changed mutation subjects"; "no mutants in the diff - nothing to gate"; 0 subjects/0 mutants, seed 1, exit 0.

COVERAGE HOLE (disclosed, per the metric contract's zero-mutant rule): the PR's change is a 2-line DELETION (a comment and an .includes eager-loading scope chain in app/models/story.rb; the app/models/user.rb change also produced no mutation subject). Mutation testing covers existing statements' behavior, not deleted lines: this row's zero mutants is a selection/operator-coverage hole, recorded separately from out-of-scope files (2182 has none). The behavioral effect of the removed scope chain is NOT mutation-verified.

INVALID/STOPPED ATTEMPTS (preserved, not counted): c1 exit 130 wall 643.98s (EX-1 left active, 859 vs 864 - process error, D53); c2 exit 130 wall 49.2s (owned stop of the unneeded per-era map once the snapshot flow was decided). No apples comparison between c1's 643.98s and this row's 11.42s: c1's setup was invalid. The 11.42s is the valid R cost with the snapshot cost amortized separately.
