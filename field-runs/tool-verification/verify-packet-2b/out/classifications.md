# Final classifications - independent verification (bundle exec, lockfile-pinned, 2026-10-24)

## Survivor candidates (4 IDs)
All four: original-code PASS of the new specimen (2204: 2 examples 0 failures; 2156: 1 example 0 failures) AND assertion-KILL of the mutant via `saboteur run --id <id> --test <specimen>` with per-mutant JSON receipts.
- 56ec2857eb8103bd, 695982748e0e8ebb, 9786b8df27eddc21 (2204, story.rb:777 score boundary): REAL TEST GAP. Whole-existing bridge: producer mechanism c091 (scoped map + whole pointer + confirmation), separate cited evidence. My inclusive all-tests run: no valid existing kill (3 rejected kills, unchanged-method Domain collision = environment noise, separate row).
- 84a2b3ca16355339 (2156, settings_controller.rb:51 condition_true): REAL TEST GAP proof legs complete; whole-existing bridge PENDING producer M/R (my scoped inclusive run cannot confirm per engine semantics; survivor UNCONFIRMED until bridge).
Note: 4 candidate IDs, not necessarily 4 distinct bugs - grouping per unit definition is the report author's call.

## Seeded kill sample (10 IDs, pool SHA256 bfe86e3f..., selection SHA256 a6965326...)
10/10 reproduced Killed, lockfile-pinned bundle exec, per-mutant JSON + --verbose logs:
- assertion (8): e4679d48fadc0ef4, 04d20954d514506c, 829cfe49830087d8, 26b630dfecabae19, f638f3e4a9d1cc1f, 65f55d1d42cd1b58 (2204); 5e66e0c9f4a67ce7 (2156); 11436dd311d9bb17 (2090)
- crash: RuntimeError (2): c48b2d39f463cdc1 (2204); a40b6c227630d3c3 (2231)
- fake kills: 0; timeouts: 0; DB-infra: 0; unresolved: 0

## EX-1 audit
CLEAN: no report JSON produced this session references spec/features/user_administration_spec.rb. Targeted spec verified GREEN (5/0) on both HEAD trees; exclusion qualified per-era, inclusive (no-EX1) whole-existing runs performed for both trees.

## Environment-noise rows (separate, not survivor classifications)
- 6 mutants in the 2204 inclusive all-tests run had kills REJECTED (killing test also fails with method unchanged: ActiveRecord::RecordInvalid "Domain has already been taken" + backtrace in JSON): 56ec2857, 69598274, 9786b8df, 5dd5baf14dad286a, ac002c38b0a84764, 906c7556be9fd7d1. UNRESOLVED in that run; class environment.
- Clock: engine-reported wall vs observed elapsed discrepancy on both inclusive runs (490s/~48min; 344s/~30.5min). OPEN, cause unknown.
- Verifier transcription bug (6 fabricated ID suffixes, exit=2): recorded, corrected, preserved; not a tool/environment defect.
