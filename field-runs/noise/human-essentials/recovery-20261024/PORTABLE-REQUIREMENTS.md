# Human Essentials portable field-run requirements (recovery checkpoint, NEW 2026-10-24; historical attempt-3 artifacts stay under ../human-essentials/attempt-3)

Status 2026-10-24 13:35 IST: zero completed study rows, zero verified bugs, doctor unfinished/no verdict. No rates. Recovery checkpoint; not execution approval.

## Sources and immutable inputs
- App: https://github.com/rubyforgood/human-essentials.git
- Doctor app head: ace6151d2296a3b252d5ccdbcc4a838caf2d388c (PR 5723).
- Study frozen main: e5e69704fc49babacb2684bf846560dcb2e63988.
- Tool source: https://github.com/vamsipavanmahesh/saboteur.git at 6f87ccc98377bf0c23f3cf409006f0464c2aa67c, gem 0.12.3. Build gem from exact source, never install registry saboteur. Attached gem rebuilt from this source, not a replacement pin.
- Published recovery source: origin/field-runs/lobsters commit 86a72fad0d2283bbdb58a6ce11fb1d515b938d54, field-runs/noise/human-essentials/attempt-3. Recovered scripts are historical artifacts, not ready-to-run portable workflow: absolute paths need parameterization and snapshot reuse changes still need review.
- Selection regenerated from current public API plus frozen git ancestry and exactly matches the frozen 15 noise and 20 bug populations. No replacement selections.

## Environment
- Linux with fork, Ruby 3.4.3, Bundler per app lock, OpenSSL/Psych/Fiddle/Prism available.
- PostgreSQL: prior local validation used 14; service database diaper_test; app reads PG_HOST and PG_USERNAME (not POSTGRES_HOST). Port 5432.
- Chrome/Chromium executable for Cuprite/Ferrum system specs, sandbox-compatible browser flags as configured in spec/rails_helper.rb. Default headless unless NOT_HEADLESS=true.
- Dependency native build headers: compiler/make, libpq, libyaml, libffi, OpenSSL, readline. Use one install/mutation worker (BUNDLE_JOBS=1, MAKEFLAGS=-j1, c.jobs=1).
- Whole suite includes system and request specs. Upstream splits these in CI and precompiles assets for the system partition; this study must not copy the partition exclusions. Asset setup is an environment step, not a test exclusion.
- Preserve app lock, Gemfile diff, effective tool config, Ruby version, tool payload manifest, test list/count, command, stdout/stderr and exit status as artifacts.

## Integration
Append only gem "saboteur", "0.12.3", group: :test to app Gemfile. Stage locally built gem in vendor/cache and install local-only after downloading ordinary locked dependencies. Fail closed if installed saboteur lib differs from unpacked built artifact. Whole packaged-gem payload audit should also be retained.

config/saboteur.rb:
```ruby
Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"]
  c.require = ["./config/environment"]
  c.rails = true
  c.jobs = 1
  c.baseline_timeout = 3600
end
```
3600s is the recorded provisional per-pass budget, not a promise of completion. Prior configured outer bound 7800s. New hosted timings must be labeled as a new environment.

## Doctor gate
Run bundle exec saboteur doctor --suite, never --test-limited. At this exact tool pin, --suite runs the unchanged suite twice internally (lib/saboteur/cli/doctor_command.rb:14; lib/saboteur/doctor.rb:41-50). Success prints "Baseline: N tests passed twice in the same order with seed ..." and returns success. Gate intent: the unchanged full suite passing twice. One successful native doctor --suite invocation satisfies that intent when both complete passes are proven at this exact pin. No redundant second invocation/four passes is required. Preserve both pass results and failure semantics; Source confirmed at the pin (6f87ccc9): doctor_command.rb:14 documents --suite as "run the unchanged suite twice"; Doctor#check_suite calls BaselineHealth once and prints the "passed twice" line; BaselineHealth#call runs check_run(1) then check_run(2) and compares them (lib/saboteur/baseline_health.rb:43-45).
- Lost attempt has no final verdict: neither pass nor fail.
- On red, preserve exact failing examples and raw output; record BLOCKED; no exclusion/replacement without a recorded per-tree failure and reviewed decision.
- No maps before the actual two-pass gate.

## Settled map routing
1. ace6151d2296a3b252d5ccdbcc4a838caf2d388c -> 5723.
2. 6453a3de3150592dc5708d4fafb3aa7e3df3270e -> 5742,5656. Lock identical; Gemfile comment typo differs for 5656, disclosed resolution-neutral.
3. 1085e87e8fda78a75910063cc59201c288e578f5 -> 5727,5541,5722.
4. 2857b48f59b58770660a3cc120d25f2170e4c1bf -> 5386,5274,5171,5606,5628,5690,5692,5686,5684. Explicit app-config drift tolerance, not zero drift. routes.rb differs for earlier members; actual commit distances are in regenerated matrix.
Follow pinned docs/ci-whole-suite-map.md: snapshot whole-suite map reused within the documented approximately two-week window; PR creates own small selection map and uses snapshot pointer confirmation. Exact-key MISS is expected. Do not force keys. Pointer alone does not prove exhaustive current-suite coverage or include new tests. Record actual confirmation IDs, hashes, snapshot, per-PR wall and drift.

## Measurement and review
Primary noise unit is per-gap (survivors grouped by statement/behavior), per-mutant secondary; report both and 95% interval. Every survivor needs independent fresh-context triage. Interim table PR/mutants/killed/survivors/gaps/verified/out-of-scope files. Out-of-scope .rb inventory attached, including spec/config/db.
Bug unit one behaviorally verified bug per fix PR. Blame is provenance, not causality. Preserved ledger has 12 old / 7 pending witness / 1 unresolved mapping, zero denominators and null outcomes. Raw line maps absent from published checkpoint; regenerate from source before treating candidate causality as verified.

No product fixes, no commercial mutant, no EX-1 exclusions, no workflow launch approval inferred from this handoff. Any hosted workflow must preserve exact-head review and established one-PR limits.
