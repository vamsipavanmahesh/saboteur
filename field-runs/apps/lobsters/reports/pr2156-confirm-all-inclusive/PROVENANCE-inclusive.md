# 2156 inclusive confirmation - run provenance (as-run)

- Command (verbatim, echoed by wrapper at log head):
  timeout 3000 bundle exec saboteur run --config config/saboteur-inclusive.rb --since 9a773eac0b49fd86b16585ad503de9a51919c496 --all --jobs 1 --baseline-passes 1 --max-duration 3600 --seed 1 --verbose --json /home/sandbox/verify/out/2156/report-confirm-all-inclusive.json
- Working tree: tree-2156 at PR 2156 merge SHA d9998c2555317db7b3cb9a159ef7878ff993ab78 (report-embedded sources sha256-match upstream), HEAD-level tree.
- Config: config/saboteur-inclusive.rb (include app/**/*.rb, NO rspec exclusions - EX-1 absent in this run; same content as 2204's, attached with the 2204 partial bundle).
- Tool: saboteur 0.12.3 via bundle exec, path gem at commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (git clean). Manifests: out/2156/loaded-specs.txt, gemfile-lock-sha.txt.
- Inclusion proof: 865 examples incl. spec/features/user_administration_spec.rb (5 examples 0 failures on this HEAD - targeted log/verdicts).
- Label: all-existing-tests coverage, scoped engine invocation (--since present => not a whole-suite-marked run per engine.rb:390), NO whole-pointer confirmation. Survivor remains UNCONFIRMED.
- Wrapper: outer `timeout 3000` (did not fire; exit=1 recorded by wrapper: 1 survivor).
- Timing (OPEN, cause unknown): engine-reported wall 344.0 s (baseline 46.4 s, map 273.8 s, mutants 13.7 s); observed elapsed ~09:16:52 -> 09:47:22 IST (~30.5 min). Same pattern as 2204 (490 s vs ~48 min).
- Result: 7 mutants = 6 Killed / 1 Survived / 0 errors. Survivor 84a2b3ca16355339 (SettingsController#update line 51 condition_true), coveredBy 2 tests, both executed, no kill. rejectedKills: see report JSON.
