# Source-compatibility check record - PR #2204 base-map restore
- saboteur 0.12.3, source SHA 6f87ccc98377bf0c23f3cf409006f0464c2aa67c
- base 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 / head ed722e449227b39ab6268f4260aaa66df95275bd
- Actions-prefix inputs (Gemfile.lock + saboteur config), committed: IDENTICAL
- CACHE_INPUTS config values (coverage_store.rb: integration require rspec_args rails tests coverage_recorder): identical in both trees (same config/saboteur.rb copied verbatim; rails=true, rspec_args=[--exclude-pattern spec/features/user_administration_spec.rb] EX-1 in both)
- spec files changed by PR (local build-key inputs, not Actions prefix): spec/models/story_spec.rb 
- consumption path: whole-suite-map-v2 pointer -> coverage-<key>.json (coverage_store.whole_suite_map, no consume-time re-hash); pointer is product trust marker (docs/ci-whole-suite-map.md)
- base inputs snapshot (base-inputs.json) captured at map build 07:42 IST; base baselines 851 ex 0 failures (EX-1 active)
