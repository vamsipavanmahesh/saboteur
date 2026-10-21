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

<a id="30-second-quick-start"></a>
## 30-second quick start

You need Ruby 3.3 or newer, RSpec, and Linux or macOS with `fork`.

Prerequisite: the sandbox layers use fiddle, which ships with Ruby
(a default gem on Ruby 3.x). On Ruby 4.0+, where fiddle is a bundled
gem, add `gem "fiddle"` to your Gemfile. If saboteur refuses a run
because fiddle cannot load: reinstall Ruby, run `gem install fiddle`,
or install libffi headers (libffi-dev on Debian/Ubuntu, libffi-devel
on Fedora/RHEL) and reinstall fiddle. libffi headers are required only
when Ruby's shipped fiddle is missing or must be installed standalone.

```sh
# Add it to your project's Gemfile:
bundle add saboteur --group test

# Then:
bundle exec saboteur run
```

Outside a Bundler project, `gem install saboteur` gives the same
executable - run it there as plain `saboteur run`, without
`bundle exec`.

The first run builds a coverage map of which tests touch which code. The
map is cached and reused while your code and tests stay unchanged, so
later runs start fast.

If the first run stops with exit 2 and `no spec found for ...`, saboteur
could not map a source file to its spec: it matches by path first, then
by parent directory and basename when the layout strips directories,
and it refuses to guess wrong. Point it at the specs yourself - set
`test_selection = :all` in `config/saboteur.rb` to run the whole suite
against each mutant, pass `--test spec/...` to name the specs, or
declare a custom map
([monorepos and the custom map](docs/guides/monorepo-and-custom-map.md)).

On a branch, `bundle exec saboteur pr` mutates only the methods you
changed relative to `main`, with one baseline pass and a ten-minute
budget. If the budget stops the run, it exits 4 and prints `partial: X
of Y mutants not run` (or says the count is unknown when planning did
not finish). Pass `--max-duration-ok` to accept a partial verdict; the
warning stays, and other failure gates still apply. Pass `--since` for a
different base, for example `bundle exec saboteur pr --since master`.

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
never change the score. The terminal prints one finding per statement with
the label mix and mutant count; `--all-mutants` lists every mutant.

A run on a tree with uncommitted changes opens with a warning that splits
the count into changes inside the mutation scope, outside it, and
saboteur's own setup files. Mutants run your code, so run on a clean,
committed tree or a CI checkout.

Code that only runs while the app loads cannot be judged by replacing the
method later, so it reports as `ran at load`, outside the score. The same
holds for def-time macros - a `deprecate`-style helper, a `before_action`
block, any DSL whose only caller is a class body: the closure captured at
load keeps the pristine definition, so the boot's def-call counters mark
the macro itself `ran at load` instead of letting its mutants survive.

## What you get

- **Fast pull-request runs.** `--since main` scopes the run to the methods
  you changed, refuses (exit 2) when the resolved range has no changes -
  `saboteur pr $GITHUB_SHA` on a checkout at the merge commit diffs the
  merge against itself - and fails loudly (exit 3) when the changed code
  cannot be verified - for example when every changed method is skipped
  because a refinement is active where it sits. A changed method skipped
  for no coverage names the specs the run loaded; when its coverage
  lives in a sibling spec file, pass `--test spec/models` (the directory
  holding it) to load it. The GitHub Action runs on every pull request
  and caches the coverage map between runs. `--shard K/N` splits one
  planned inventory deterministically across CI jobs; each shard reports
  partial evidence.
- **Honest verdicts.** Every kill is verified against the unchanged
  method; a kill the suite cannot confirm stays out of the score.
  Suspect a flaky test? `--flaky-check survivors` confirms each new
  survivor with one reordered rerun (`decisive` also confirms fresh
  kills); a verdict the rerun disagrees with becomes `unverified`,
  named with its tests, and stays out of the score. A spec
  file whose examples depend on earlier ones is retried in defined order
  before a kill is rejected, so its mutants are still scored.
- **Reports for people and tools.** Terminal, HTML, a Stryker-compatible
  JSON report, and a stable agent JSON API with a deprecation policy.
  The GitHub Action posts surviving mutants as review comments on the
  diff lines of the pull request.
- **Resumable runs.** `--resume DIR` keeps verdicts across runs and
  `--incremental` checkpoints them while the run is going, so a stopped
  run picks up where it left off.
- **Faster coverage builds.** `c.coverage_parts` builds the coverage map
  in parallel parts, `partial_coverage = "use"` rebuilds only the stale
  spec files and merges them into the saved map, and
  `c.coverage_recorder = "trace"` builds the map with a TracePoint
  recorder.
- **A plan before the run.** `saboteur run --dry-run --format json` prints
  the versioned [mutant inventory](docs/dry-run-json.md) - every planned
  mutant with its stable digest and edits - without booting the suite.
- **A review workflow.** An ignore list with reasons and triage states,
  an opt-in survivor baseline, score thresholds and score history.
  `saboteur survivors .saboteur/report.json` browses survivors in the
  terminal straight from the JSON report - list, filter
  (`--file`/`--operator`/`--triage`/`--ranked`), and `--show DIGEST`
  for the diff, the exact `run --id` replay command and an ignore-file
  entry template. It never boots your project or edits the ignore file.
- **A local README badge.** `saboteur badge` writes Shields endpoint JSON
  from the score history and `saboteur trend` prints the score delta -
  no hosted service:

  ```md
  ![mutation score](https://img.shields.io/endpoint?url=<raw-url-of-the-badge-json>)
  ```

  Incomplete runs are refused as badge evidence unless `--mark-partial`
  labels them, and the trend never compares runs with different
  selection, inventory or operator policy.
- **Safety controls.** A hazard guard, canary values, and time, memory
  and process-count limits on every mutant in the default in-process
  mode; a Landlock sandbox on Linux
  6.2 and newer.
- **Extension points.** Add your own mutation operators through the
  public interface.

Per-path score gates hold one subtree to a stricter floor: `c.score_gate
"app/payments/**/*", min_score: 95` in config/saboteur.rb (repeatable). Each
gate scores only the mutants under its pattern and fails the run under its
floor; a gate with nothing executed under it passes vacuously and says so.
See
[choosing and raising a threshold](docs/best-practices.md#choosing-and-raising-a-threshold)
for how to pick a number.

## Honest limits

- saboteur is RSpec-only and needs `fork`: no Windows, no Minitest.
- A survivor is review evidence, not proof of a bug in your tests. It can
  be a missing test, an equivalent change, a flaky test, or a limit of
  the tool. Read it before you write a test for it.
- `--since` and `--incremental` are iteration aids. Run the whole project
  on main and before a release.
- The hazard guard is syntactic, sandboxing varies by platform (Landlock
  on Linux 6.2+; on macOS mutants run unsandboxed unless `c.sandbox = "seatbelt"`
  opts into a probe-gated Seatbelt profile; see
  [the macOS Seatbelt sandbox](docs/guides/macos-seatbelt-sandbox.md)), and network access is
  never restricted. Stub real APIs and use a container when that matters.

### Custom spec mapping

When the naming guess does not fit the project's layout, teach the mapping
once in `config/saboteur_custom_map.rb` instead of passing `--test` on every
run:

```ruby
SABOTEUR_CUSTOM_MAP = {
  "lib/aasm/core/state.rb" => ["spec/unit/state_spec.rb"],
  "app/jobs/**/*.rb"       => ["spec/jobs/**/*_spec.rb"],
  %r{\Aapp/jobs/(.*)\.rb\z} => ['spec/jobs/\1_spec.rb'],
  "app/generated/**/*.rb"  => [], # intentionally untested
}.freeze
```

A matching entry wins over the naming convention: the file stops being
unmatched and its mapped specs run as the inferred ones. Keys are exact
paths, globs or Regexps; an empty array marks the file intentionally
untested, so it needs no inferred spec. The file loads before the app
boots, so keep it plain Ruby. `saboteur doctor` validates it.

### Rejected kills

The terminal lists them in a `Rejected kills` section and annotates the error
count (`error 3 (2 rejected kills)`); JSON flags each rejected mutant with
`rejectedKill: true` and keeps the `rejectedKills` count. These are fresh
per-mutant kill claims whose tests also fail with the method unchanged. They
stay errors outside the score. Timeout checks, other errors and reused cached
kills are not included. See [rejected kills](docs/rejected-kills.md) for
details.

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
  c.include = ["app/**/*.rb"]         # spec/test dirs vendored under lib/ are excluded by default
  c.require = ["./config/environment"] # boots the app
  c.rails = true                       # reconnects ActiveRecord after fork, per-worker databases
  c.jobs = 4                           # optional; the default is 1
end
```

An engine gem whose specs live under `spec/dummy` needs an exclude for them; see
[Rails engines and dummy apps](docs/guides/rails-engines-and-dummy-apps.md).

## SimpleCov

saboteur needs Ruby's `Coverage` for itself, so leave SimpleCov off for
saboteur runs - for example, start it only when `ENV["COVERAGE"]` is set.
The [recipes](docs/recipes/README.md) cover this and VCR, WebMock and
Sidekiq.

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

## Disclaimer

saboteur is provided "as is", without warranty of any kind, express or
implied. In no event shall the authors or copyright holders be liable
for any claim, damages or other liability arising from its use -
including damage caused by mutating your code or by running unusual
DSLs and metaprogramming-heavy code. Mutation testing runs your test
suite against deliberately broken code; run it on a clean, committed
tree or a CI checkout. The full text is in [LICENSE](LICENSE).

## License

[MIT](LICENSE).
