# 2204 inclusive confirmation - run provenance (as-run)

- Command (verbatim, echoed by wrapper at log head):
  timeout 3000 bundle exec saboteur run --config config/saboteur-inclusive.rb --since 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 --all --jobs 1 --baseline-passes 1 --max-duration 3600 --seed 1 --verbose --json /home/sandbox/verify/out/2204/report-confirm-all-inclusive.json
- Working tree: tree-2204 at PR 2204 merge SHA ed722e4492 (report-embedded sources sha256-match upstream), HEAD-level tree.
- Config: config/saboteur-inclusive.rb attached (include app/**/*.rb, NO rspec exclusions - the EX-1 exclusion is absent in this run).
- Tool: saboteur 0.12.3 via bundle exec, loaded from path gem /home/sandbox/verify/saboteur-src at commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (git clean). Loaded-deps manifest: out/2204/loaded-specs.txt; Gemfile.lock SHA in out/2204/gemfile-lock-sha.txt.
- Inclusion proof: coverage map 861 tests = 856 (EX-1 suite) + 5 (user_administration feature scenarios, verified green 5 examples 0 failures on this HEAD before the run - see targeted log/verdicts).
- Wrapper: outer `timeout 3000` (did not fire; run completed inside it, exit=0 recorded by wrapper).
- Timing (OPEN, cause unknown): engine-reported wall 490.26 s (baseline 36.0 s, map 252.5 s, mutants 193.3 s). Observed file-to-file elapsed 08:28:46 -> 09:16:52 IST (~48 min). Engine wall does not account for observed elapsed; no stall cause claimed.
- Result: 22 mutants = 16 Killed / 0 Survived / 6 RuntimeError (all 6 = rejected kills: "killing test also fails with the method unchanged", verbatim causes in report JSON statusReason). Exit 0.
- Class status: the 6 RuntimeError mutants are UNRESOLVED (not Survived, not real-gap-confirmed): 56ec2857eb8103bd, 695982748e0e8ebb, 9786b8df27eddc21 (producer survivors), 5dd5baf14dad286a, ac002c38b0a84764, 906c7556be9fd7d1 (producer-killed). Fact: their killing tests fail on unchanged code in this run. Subset-ordering explanation is a hypothesis, not reproduced.
