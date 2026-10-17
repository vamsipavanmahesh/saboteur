<p align="center">
  <img src="assets/logo.png" alt="saboteur logo: a ninja beetle with a ruby shell carrying a lit bomb" width="200">
</p>

# saboteur

**Mutation testing for Ruby and RSpec, built for pull requests.** 🧨

[![CI](https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml/badge.svg)](https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/saboteur)](https://rubygems.org/gems/saboteur)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Line coverage tells you which code ran. It does not tell you if a test
would notice when that code breaks. Mutation testing does.

saboteur makes one small change to your code at a time and runs only the
tests that touch it, so it is fast. If the tests still pass, you see the
exact change they missed. Every kill is re-checked against the unchanged
code, so a broken suite never counts as a kill.

**Docs, benchmarks and guides live on the site:
[vamsipavanmahesh.github.io/saboteur](https://vamsipavanmahesh.github.io/saboteur/)**

<a id="60-second-quick-start"></a>
## 30-second quick start

You need Ruby 3.3 or newer, RSpec, and Linux or macOS with `fork`.

```sh
gem install saboteur
# or: bundle add saboteur --group test
bundle exec saboteur run
```

The first run builds a coverage map of which tests touch which code. The
map is cached and reused while your code and tests stay unchanged, so
later runs start fast.

On a branch, `bundle exec saboteur pr` mutates only the methods you
changed, with one baseline pass and a ten-minute budget.

Setup, configuration and CI:
[the quickstart](https://vamsipavanmahesh.github.io/saboteur/quickstart.html).

## Why RSpec-only

A mutation verdict is only worth anything if the test selection behind it
is exact. RSpec's example structure lets saboteur map each method to the
examples that cover it, rerun just those against each change, and re-check
every kill against the code before the change. One framework, done
properly - that is the bet. Minitest is not supported today;
[why, and what it would take](docs/minitest.md).

## What a run tells you

```text
saboteur 0.7.0: 1 subjects, 10 mutants, wall 0.70 s, seed 1
killed 8  survived 2  timeout 0  resource limit 0  error 0  score 80.0 %
```

Each survivor comes with its diff, the tests that ran, and a triage label
(`likely_equivalent`, `arid`, `missing_test`) to sort what to read first.
The labels are heuristics for reading order, never a diagnosis, and they
never change the score.

## What you get

- **Fast pull-request runs.** `--since main` scopes the run to the methods
  you changed. The GitHub Action runs on every pull request and caches
  the coverage map between runs.
- **Honest verdicts.** Every kill is verified against the unchanged
  method; a kill the suite cannot confirm stays out of the score.
- **Reports for people and tools.** Terminal, HTML, a Stryker-compatible
  JSON report, and a stable agent JSON API with a deprecation policy.
- **A review workflow.** An ignore list with reasons and triage states,
  an opt-in survivor baseline, score thresholds and score history.
- **Safety controls.** A hazard guard, canary values, and time, memory
  and process-count limits on every mutant; a Landlock sandbox on Linux
  6.2 and newer.
- **Extension points.** Add your own mutation operators through the
  public interface.

## Honest limits

- saboteur is RSpec-only and needs `fork`: no Windows, no Minitest.
- A survivor is review evidence, not proof of a bug in your tests. It can
  be a missing test, an equivalent change, a flaky test, or a limit of
  the tool. Read it before you write a test for it.
- `--since` and `--incremental` are iteration aids. Run the whole project
  on main and before a release.
- The hazard guard is syntactic, sandboxing varies by platform (Landlock
  on Linux 6.2+; mutants run unsandboxed on macOS), and network access is
  never restricted. Stub real APIs and use a container when that matters.

### Rails apps

Quickstart for a Rails + RSpec app. The defaults target a plain gem, so a
Rails app needs a few settings; the generator writes them for you:

```sh
bundle add saboteur --group test
bundle exec rails generate saboteur:install
```

This writes `config/saboteur.rb`, a `bin/saboteur` binstub (it sets
`RAILS_ENV=test` for you) and a `.gitignore` entry for `.saboteur/`. It
never overwrites an existing file unless you pass `--force`.

Until a config names your sources, a run whose include selects no Ruby
file refuses with exit 2 and points at the install generator above -
a first CI run on an unconfigured tree fails loud instead of passing
with 0 subjects.

Prefer to do it by hand, or on a version without the generator? Put this
in `config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.include = ["app/**/*.rb"]
  c.require = ["./config/environment"] # boots the app
  c.rails = true                       # reconnects ActiveRecord after fork, per-worker databases
  c.jobs = 4                           # optional; the default is 1
end
```

<a id="dated-validation-runs"></a>
<a id="where-it-has-run"></a>
## Benchmarks and validation

Speed and memory numbers live with the harness and the raw data that
reproduce them, framed as dated measurements rather than standing claims:
the [benchmarks page](https://vamsipavanmahesh.github.io/saboteur/benchmark/)
on the site and [docs/benchmark](docs/benchmark/) in this repo.

## Project

- [Changelog](CHANGELOG.md)
- [All documentation](docs/README.md) - configuration, operators, CI, recipes
- [Contributing](CONTRIBUTING.md) - every commit needs a DCO `Signed-off-by` line
- [Design notes](docs/design.md)

## License

[MIT](LICENSE).
