<p align="center">
  <img src="assets/logo.png" alt="saboteur logo: a ninja beetle with a ruby shell carrying a lit bomb" width="200">
</p>

<h1 align="center">saboteur</h1>

<p align="center">
  <strong>Mutation testing for Ruby and RSpec, built for pull requests.</strong><br>
  Line coverage tells you which code ran. saboteur tells you whether your tests would notice when it breaks.
</p>

<p align="center">
  <a href="https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml"><img src="https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/saboteur"><img src="https://img.shields.io/gem/v/saboteur" alt="Gem Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
</p>

```text
$ bundle exec saboteur pr
saboteur 0.11.0: 2 subjects, 10 mutants, wall 0.70 s, seed 1 (repeat with --seed 1)
Score: 80.0% (8/10 killed, tested subjects)
saboteur: 8 killed, 2 survived in 1s - score 80.0%
```

A survivor is a change to your code that your tests waved through.
saboteur breaks your code one small change at a time, runs only the tests
that touch it, and shows you the exact change they missed. Every kill is
re-checked against the unchanged code, so a broken suite never counts as
a kill. A green run here actually means something.

## Get started in 3 steps

```sh
# 1. Add it to your project's Gemfile
bundle add saboteur --group test

# 2. Run it (the first run builds a cached coverage map)
bundle exec saboteur run

# 3. Put it on every pull request - mutates only what you changed vs main
bundle exec saboteur pr
```

On GitHub Actions, `bundle exec saboteur install` writes the two workflows
that build the whole-suite map on main and restore it on every pull request
(see [the CI map guide](docs/ci-whole-suite-map.md)).

You need Ruby 3.3 or newer, RSpec, and Linux or macOS with `fork`. The
sandbox layers use fiddle, which ships with Ruby; on Ruby 4.0+, where
fiddle is a bundled gem, add `gem "fiddle"` to your Gemfile. Outside
a Bundler project, `gem install saboteur` gives the same executable.
Rails app? `bundle exec rails generate saboteur:install` writes the config
for you. Full setup:
[the quickstart](https://vamsipavanmahesh.github.io/saboteur/quickstart.html).

### Rails apps

`bundle exec rails generate saboteur:install` writes the config for you.
By hand, put this in `config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.include = ["app/**/*.rb"]         # spec/test dirs vendored under lib/ are excluded by default
  c.require = ["./config/environment"] # boots the app
  c.rails = true                       # reconnects ActiveRecord after fork, per-worker databases
  c.jobs = 4                           # optional; the default is 1
end
```

The defaults target a plain gem, so a first run on an unconfigured Rails
tree refuses with exit 2 and points at the generator. Engine gem with
`spec/dummy`? See
[Rails engines and dummy apps](docs/guides/rails-engines-and-dummy-apps.md).

## Highlights

- ⚡ **Fast by scope.** `--since main` mutates only the methods you
  changed, `saboteur pr` adds one baseline pass and a ten-minute budget,
  and `--shard K/N` splits one planned inventory deterministically across
   (e2e: spec/e2e/since_changed_specs_spec.rb) (e2e: spec/e2e/presets_spec.rb) (e2e: spec/e2e/shard_spec.rb)
- 🎯 **A score that tells the truth.** The score covers tested subjects
  only. A method no test covers is named in a `Not scored` list instead of
  padding the number, kills split by cause (`kills: 7 by a failed
  assertion, 1 by a crash`), and an error-dominated run prints
  `Score: n/a`  (e2e: spec/e2e/output_polish_spec.rb) (e2e: spec/e2e/kill_causes_spec.rb) (e2e: spec/e2e/score_na_spec.rb)
- 🔍 **Survivors you can act on.** Survivors group per statement with a
  triage label (`likely_equivalent`, `arid`, `tool_limit`, `input_gap` (the tests
  never gave the mutated expression an input where its value differs, or no
  test reached it), `assertion_gap` (the value changed and the tests still
  passed), or a gap kind) and their
  covering tests - split into the tests that ran against the mutant and
  the ones that never did. `saboteur survivors` browses them read-only:
   (e2e: spec/e2e/survivor_triage_spec.rb) (e2e: spec/e2e/gap_kind_labels_spec.rb) (e2e: spec/e2e/replay_spec.rb)
- 🧪 **Flakiness contained.** `--flaky-check survivors` re-runs each new
  survivor in a reordered confirmation pass; a verdict the rerun disagrees
  with becomes `unverified` and stays out of the score. With
  `partial_coverage = "use"`, open
  survivors get one budgeted confirmation run against the covering specs
  that never ran them when the map is built from every spec (`--all`, no
  `--test`, one coverage part, cache on). Default inferred-spec runs, `pr`
  included, skip it. (e2e: spec/e2e/flaky_check_spec.rb) (e2e: spec/e2e/scoped_confirmation_spec.rb)
- 📊 **Reports for people and tools.** Terminal, HTML, a Stryker-compatible
  JSON report, and a stable agent JSON API with a deprecation policy. The
  GitHub Action posts survivors as review comments on your PR diff lines.
  `saboteur badge` and `saboteur trend` track the score history with no
  hosted service. (e2e: spec/e2e/stryker_schema_spec.rb) (e2e: spec/e2e/html_viewer_spec.rb) (e2e: spec/e2e/score_history_spec.rb)
- 🛡️ **Safe to point at real code.** A hazard guard, canary values, and
  time, memory and process-count limits on every mutant; a Landlock
  sandbox on Linux 6.2+ and an opt-in Seatbelt profile on macOS. (e2e: spec/e2e/hazard_guard_spec.rb) (e2e: spec/e2e/containment_spec.rb) (e2e: spec/e2e/seatbelt_spec.rb)
- 🧭 **A plan before the run.** `--dry-run --format json` prints the
  versioned mutant inventory - every planned mutant with its stable digest
  and edits - without booting your suite. (e2e: spec/e2e/dry_run_inventory_spec.rb)
- 🔁 **Built for big suites.** `--resume` and `--incremental` pick up
  where a stopped run left off, parallel coverage builds
  (`c.coverage_parts`) and a TracePoint recorder keep the map cheap, and
  per-path score gates hold one subtree to a stricter floor. (e2e: spec/e2e/phase3_spec.rb) (e2e: spec/e2e/coverage_build_modes_spec.rb) (e2e: spec/e2e/score_gates_spec.rb)

## Exit codes that mean something

| Exit | Meaning |
| --- | --- |
| 0 | Clean: no unignored survivors, every gate passed |
| 1 | Survivors to review, or a gate failed |
| 2 | Usage or configuration error |
| 3 | Incomplete: tested nothing, mostly errored, or the change is unverified |
| 4 | The `--max-duration` budget stopped the run early |
| 5 | Your unchanged suite already fails its baseline - fix your tests first |
| 70 | An internal crash: a saboteur bug, never your code; the error names a log with the full backtrace |

## Know the limits

- RSpec-only, and no Minitest ([why, and what it would
  take](docs/minitest.md)). (e2e: spec/e2e/minitest_project_spec.rb)
  It also needs `fork` - a Ruby platform constraint, not saboteur
  behavior - so no Windows. (e2e: spec/e2e/fork_required_spec.rb)
- saboteur needs Ruby's `Coverage` for itself, so leave SimpleCov off for
  saboteur runs - start it only when `ENV["COVERAGE"]` is set
  ([recipes](docs/recipes/README.md)). (e2e: spec/e2e/simplecov_coexistence_spec.rb)
- A survivor is review evidence, not proof of a bug in your tests. It can
  be a missing test, an equivalent change, a flaky test, or a limit of
  the tool. Read it before you write a test for it. (e2e: spec/e2e/survivor_triage_spec.rb)
- A survivor can be false when the test that kills it lives in a spec
  file saboteur did not select. Runs without `--test` pick specs by file
  name and by the constants they read, so a test in a differently named
  spec (say `spec/integration/flow_spec.rb` for `lib/ledger/router.rb`)
  may never run against the mutant, and the "covered by ... ran, still
  passed" lines list the specs that ran, plus any others marked "not run
  here". If you know
  another spec exercises the code, run again with `--test` naming it
  before you trust the survivor. (e2e: spec/e2e/reference_selection_spec.rb) (e2e: spec/e2e/explicit_files_spec.rb) (e2e: spec/e2e/inference_miss_spec.rb)
- `--since` and `--incremental` are iteration aids. Run the whole project
  on main and before a release. (e2e: spec/e2e/phase3_spec.rb) (e2e: spec/e2e/since_changed_specs_spec.rb)
- Sandboxing varies by platform and network access is never restricted.
  Stub real APIs and use a container when that matters. (e2e: spec/e2e/seatbelt_spec.rb) (e2e: spec/e2e/network_unrestricted_spec.rb)

## Docs

- [Quickstart and guides](https://vamsipavanmahesh.github.io/saboteur/quickstart.html) - setup, CI, recipes
- [All documentation](docs/README.md) - configuration, operators, recipes
- [Changelog](CHANGELOG.md)
- [Benchmarks](https://vamsipavanmahesh.github.io/saboteur/benchmark/) - dated measurements with the raw data
- [Contributing](CONTRIBUTING.md) - every commit needs a DCO `Signed-off-by` line

## Disclaimer

saboteur is provided "as is", without warranty of any kind. Mutation
testing runs your test suite against deliberately broken code; run it on a
clean, committed tree or a CI checkout. The full text is in
[LICENSE](LICENSE).

## License

[MIT](LICENSE).
