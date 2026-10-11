<p align="center">
  <img src="assets/logo.png" alt="saboteur logo: a ninja beetle with a ruby shell carrying a lit bomb" width="200">
</p>

# saboteur

**Mutation testing for Ruby and RSpec, built for pull requests.** 🧨

[![CI](https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml/badge.svg)](https://github.com/vamsipavanmahesh/saboteur/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/saboteur)](https://rubygems.org/gems/saboteur)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Your suite is green and coverage says 95%. That tells you the tests *ran* your
code. It does not tell you they would *notice* if the code were wrong.

saboteur finds out. It makes small deliberate changes to your methods (flips a
`<` to `<=`, swaps `+` for `-`, replaces a body with `nil`), runs the tests that
cover each change, and reports every change your suite let through. Each of
those survivors can point at a missing test. It can also be an equivalent
change that no test could notice, a flaky test, or a limit of the tool, so
each one needs a human look.

```
$ bundle exec saboteur run --since origin/main
```

Never heard of mutation testing? It asks "if I broke this, would a test
fail?" for many small breakages and lists the ones nobody noticed. Read the
[design notes](docs/design.md) when you want the details. For adopting it on a team, see the
[best practices guide](docs/best-practices.md).

### The unchanged suite is checked first

Every run with selected subjects runs the entire unchanged suite twice in fresh
supervised children before coverage lookup or incremental verdict reuse. This
costs two suite runs even on a cache hit, plus a coverage-building suite run on
a cache miss. Both baseline passes must be green, complete and in the same
RSpec order at the run seed. A failure exits 3, stops mutation and names the log and fix. Each suite pass
uses `coverage_timeout` and configured memory/process limits (the suite memory
budget is four times `max_memory_mb`, as for coverage). Older benchmark numbers
need a rerun before they describe this extra fixed cost.
A whole-suite coverage build that records no lines for any included file
means the setup hid the app from Coverage (Bootsnap's compile cache is the
common cause), so the run fails with exit 3 instead of testing nothing, and
the empty map is not cached. With `--test` an empty map instead stays a
legitimate "no coverage" outcome, because the chosen specs may not touch the
selected sources.
Two passes detect observed instability, not every possible flaky test. See
[baseline stability](docs/baseline-stability.md) for limits and hook behaviour.


## 🚀 Try it in a minute

Add saboteur to the test group of your project's Gemfile (Ruby 3.3+, RSpec):

```ruby
gem "saboteur", group: :test
```

```sh
bundle install
bundle exec saboteur run --subject 'YourClass#your_method'
```

Outside a Bundler project, `gem install saboteur` installs the same executable.
Rails apps need a Rails block in `.saboteur.yml` (boot file, `app/**/*.rb`,
`rails: true`); see [Rails apps](#rails-apps) below. The defaults are for plain
gems (`lib/**/*.rb`, `rails: false`, `jobs: 1`) and are not Rails-aware.

Start with one method. You get counts per status, a score, timing, and a
unified diff for every survivor, so you can read the exact change your tests
missed. The JSON report lands in `.saboteur/report.json`.

📋 Requirements: Ruby 3.3 or newer on Linux or macOS (it needs `fork`), and RSpec.

## 🧠 Why it is built the way it is

**It only runs tests that can matter.** Each mutant runs only the tests whose
line coverage touched the changed statement. Tests that killed earlier mutants
of the same method go first, then the fastest, and the first failure stops the
run. A change no test reaches is reported as "no coverage", not as a survivor.

**It does not waste time on dead ends.** Each method first gets whole-body
mutants (`nil` and `raise`, or `true`/`false` for predicates; a few methods,
such as some that rescue or log, get none). If your suite does not notice
that, saboteur says so and skips the fine-grained mutants for that method. Subjects with no tests
are skipped before any mutants are generated, and each method is capped at
`max_mutants_per_method` mutants (100 by default).

**It prepares memory before it forks.** Before workers fork, saboteur warms and
compacts the Ruby heap ([`ForkReadiness`](lib/saboteur/execution/fork_readiness.rb)),
which is meant to let workers share more pages with their parent and copy less.
The physical-memory benefit is not yet established by a published benchmark.

**It is aimed at pull requests.** `--since origin/main` mutates only the methods
your branch changed: fine-grained mutants on the changed lines, plus the
whole-body mutants of those methods. On one real change in saboteur's own history, that took a file
from 139 mutants to 7, and median wall time fell 22.9%. The time saving is
smaller than the mutant count because building the coverage map is a fixed
cost, and this is one file, not a Rails app, so it is not a general speed
claim. The full method, raw timings and
caveats are in [bench/since](bench/since/README.md).

**It checks its own kills.** After a method's mutants run, saboteur re-runs the
killing tests against the *unchanged* method. If they fail there too, the kill
is not credited and becomes an error. In our comparison on lobsters, 0 of 20
checked kills were fake. Every mutant runs in a supervised child with deadline,
memory and process limits, and saboteur tracks and kills the processes it
starts.

**It is open.** The report is JSON in the Stryker mutation-testing-report
schema, and you can add your own mutants through a small public interface.

## 🛠️ Usage

```sh
bundle exec saboteur run                          # whole project
bundle exec saboteur doctor --seed 42             # environment + two unchanged suite checks
bundle exec saboteur run --since origin/main      # methods changed on this branch
bundle exec saboteur run --subject 'Billing::Invoice#total'
bundle exec saboteur run --subject Billing        # a namespace
bundle exec saboteur run --incremental            # reuse verdicts whose inputs did not change
bundle exec saboteur run --seed 1234              # repeat a run that used seed 1234
bundle exec saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb --test spec/b_spec.rb
bundle exec saboteur run --threshold 90           # exit 1 when the score is below 90 %
bundle exec saboteur run --id DIGEST --seed 1234  # replay one full current mutant digest
```

Positional operands name the sources to mutate: Ruby files, or directories
(all their `.rb` files). Each must exist; a typo or a non-Ruby file exits 2
before anything runs. They replace `include` and `exclude`. `--test`
(repeatable; spec files or directories, with an optional `:LINE` or `[1:2]`
selector; needs at least one source) replaces only the files RSpec runs. Other
`rspec_args` and `.rspec` options such as `--require` stay. The coverage map
is built from only those specs, each mutant runs only the ones that cover it,
and the selection is part of the coverage and `--incremental` cache keys.

`--threshold PERCENT` (0 to 100, or `threshold:` in `.saboteur.yml`) is for CI.
The run exits 1 when the score is below PERCENT and 0 when it is at or above,
even with survivors. It fails closed: a run that tested no mutant has no score
and exits 1, and a run where any mutant errored or hit a resource limit exits 3,
because the score covers only part of the run. Without a threshold, any
unignored survivor exits 1.

Other flags: `--jobs N` (concurrent workers), `--timeout-factor N`,
`--config PATH`, `--integration NAME`, `--reeval class_eval|nesting`,
`--json PATH`, `--no-cache` (rebuild the coverage map).

For pull requests, start with `--since` against your target branch. This is a
workflow recommendation, not a CLI default: plain `run` still checks the whole
configured project. Keep whole-project runs on main: diff mode does not check every method affected by a
dependency change. [The pull-request guide](docs/pull-requests.md) covers
checkout history, a GitHub Actions example, configuration and limits.

`saboteur doctor` prints Ruby, coverage, integration, Rails/SimpleCov and boot-file
checks, then runs the unchanged suite twice with the chosen seed. It writes no
mutation reports or coverage/verdict caches. Target boot files and tests still
run, so their normal side effects remain. See the [doctor guide](docs/guides/doctor.md).

`--id` runs exactly one current mutant with its coverage-selected tests, bypassing
per-method caps, coarse gating, ignore suppression and incremental verdict reuse.
It still honors `--subject` and `--since` changed-line selection. See the
[replay guide](docs/guides/replay.md) for digest format, checks and limits.

Every test run starts from the same random seed (1 by default), so tests that
use `rand` see the same values in each mutant's run and in the check that
confirms a kill. The report prints the seed; pass it to `--seed` to repeat a
run.

`--incremental` reuses an earlier verdict only while the method, the mutant,
its covering tests and their files, the lockfile and the config are all
unchanged. It cannot see a change in a method this one calls, so run without
it now and then (and in CI on the main branch).

Output: counts per status, the score, timing, and a unified diff for every
survivor. Under each diff the terminal lists the tests that covered that line
and still passed with the mutant applied (the first five, likeliest killers
first; the rest are under `coveredBy` in the JSON report). The missing
check may belong in one of them. Line coverage can overstate which tests
exercise a line, so treat the list as a lead. A survivor reused with
`--incremental` was not run again, and the list says its tests passed in an
earlier run. The HTML page shows the same list in the
survivor's notes. The JSON report goes to `.saboteur/report.json` and a self-contained HTML
report (one file, no scripts, no network) to `.saboteur/report.html`. Change
the paths with `--json` / `--html` or `json_report` / `html_report` in
`.saboteur.yml`; set either to `null` to turn that report off. The two paths
must differ. The HTML page shows the covered mutation score
`(killed + timeout) / (killed + survived + timeout)`, which leaves NoCoverage
out and keeps survivors accepted on the ignore list in the denominator. A tool
that reads the JSON report may show a different score, because the schema counts
NoCoverage as undetected.

For code-review surfaces, the JSON report also carries a `saboteur.findings`
section: a bounded, deterministically ordered list of survivors, coarse
mutants first (a surviving coarse mutant hints that no test pins the method's
behavior - it can also be a re-evaluation limit or an equivalent mutant),
then file, line and digest. Each finding holds the file, line, digest,
subject, operator, original and replacement a note on a pull-request diff
needs, plus one entry per edit for mutants that edit more than one spot.
Survivors accepted on the ignore list are listed separately with their
reason, and `survivorsTruncated` and `acceptedTruncated` count what the bound
left out; the full data stays in the schema's `files` section.

Exit codes: 0 no survivors (or all on the ignore list), or the score meets
`--threshold`; 1 survivors, or the score is below `--threshold` or missing;
2 bad configuration or a missing source or test; 3 the tool failed (with
`--threshold`, also any errored or resource-limited mutant).

### Rejected kills

The terminal prints `kills rejected by unchanged-method check: N`; JSON adds
`rejectedKills`. This counts fresh per-mutant kill claims whose tests also fail
with the method unchanged. They stay errors outside the score. Timeout checks,
other errors and reused cached kills are not included. See
[rejected kills](docs/rejected-kills.md) for details.

## ⚙️ Configuration

`.saboteur.yml` in the project root; CLI flags override it. Keep the shared
config usable for whole-project runs and pass `--since` in the pull-request
job. A PR-only config may set `since: origin/main`; omit `since` (or use
`since: null`) in the config for audits on main. Use your actual target branch.

```yaml
include: [lib/**/*.rb]
exclude: [lib/my_gem/version.rb]
require: []                 # boot files, e.g. ./config/environment
reeval: nesting             # or class_eval; see docs/design.md 6.1
timeout_factor: 3           # per-mutant deadline = factor x its tests' recorded time
timeout_min: 5
max_memory_mb: 2048         # memory growth cap per mutant process tree
max_processes: 64
max_mutants_per_method: 100  # positive integer; raise it for a broader run
ignore_file: .saboteur-ignore.yml
seed: 1                     # Ruby's random seed in every test run
```

### Rails apps

The defaults target a plain gem, so a Rails app needs this in `.saboteur.yml`:

```yaml
include: [app/**/*.rb]
require: [./config/environment]   # boots the app
rails: true                       # reconnects ActiveRecord after fork, per-worker databases
jobs: 4                           # optional; the default is 1
```

Run with `RAILS_ENV=test` and turn SimpleCov off for the run. An install
generator is planned; until then this block is the supported setup.

Bootsnap needs no extra setting: bytecode from its compile cache carries no
coverage counters, so saboteur sets `DISABLE_BOOTSNAP_COMPILE_CACHE=1` for its
own process when the variable is not already set (Bootsnap treats any set
value as off) and runs the eager load with Coverage active. App code is seen
by Coverage with the app unchanged.

With `jobs: 4` (or more), each extra worker gets a copy of every test
database, named `<database>_saboteur2` and up, made with
`CREATE DATABASE ... TEMPLATE` on Postgres or a file copy on SQLite.
saboteur drops the copies when the run ends, on a best-effort basis: a
drop that fails is reported as a warning and never changes the run's
outcome. A copy left behind - by a failed drop or a killed run - is
reclaimed by the next run, whose prepare starts from
`DROP DATABASE IF EXISTS`. MySQL is not supported for `jobs` above 1.

### Skipped subjects and the mutant cap

Subjects with no test coverage are skipped before mutation sources run. They
remain in the subject count, are listed as skipped subjects in terminal output,
and appear under `skippedSubjects` in JSON. They are not invented mutants and do
not enter saboteur's mutation score. Stryker dashboards may ignore the extra
`skippedSubjects` field and calculate scores from mutant entries alone, so
removing previously generated `NoCoverage` mutants can raise a dashboard's score
even when test detection has not improved. Changes inside a covered method that
no test reaches still produce mutant-level "no coverage" results.

Each covered method keeps at most `max_mutants_per_method` valid, distinct
mutants (100 by default). Coarse mutants come first, then fine mutants in
configured mutation-source order and each source's proposal order. The cap keeps
a prefix of that order, so earlier sources can use the entire limit within a
method. Later methods have their own limit. In diff mode, changed-line selection
happens before the cap. A warning names each capped method and the number
omitted; JSON keeps these warnings under `warnings`. The score describes this
selected subset, not every possible mutation. Raise the limit to examine more
mutants; the limit does not bound how many proposals a custom source creates.

### Ignoring a survivor

Every survivor is printed with a digest. Accept it with a reason:

```yaml
# .saboteur-ignore.yml
- subject: "Billing::Invoice#total"
  mutation: "1a2b3c4d5e6f7a8b"
  reason: "equivalent: amounts are always whole cents"
```

An entry without a reason is rejected.

### SimpleCov

saboteur needs Ruby's `Coverage` for itself. Disable SimpleCov for the run
(most projects already guard it with an environment variable).

## Filter mutations

The built-in source also swaps `select` / `reject` and `select!` / `reject!`.
These catch a filter that keeps the items it should discard (or discards the
items it should keep). For example, a command replacement should remove the
old command, not keep only that command:

```ruby
commands.reject! { |name, _| name == replaced_name }
# mutant: commands.select! { |name, _| name == replaced_name }
```

Only explicit-receiver calls with a block and no ordinary arguments are
changed. A block passed as `&predicate` counts; safe navigation is preserved.
`relation.select(:name)`, bare `select { ... }`, and `items.select` without a
block are not changed. Arid statements and nested definitions remain skipped.
Ruby dispatch is dynamic: a matching name does not prove the receiver is an
Enumerable, and a custom receiver can make the replacement fail. No type or
real-fault detection guarantee is made.

These are fine mutants, appended after the existing built-in operators. For unchanged subjects, old
mutant digests and relative order stay unchanged, but runs can produce more
mutants, change their score, and hit the per-method cap. The operator and source
name in reports is `filter_replacement`.

See [the operator rationale](docs/filter-operators.md) for the Ruby fault used
to choose this family and the limits of that evidence.

## Literal mutations

Builtin now swaps `true` / `false` literals and replaces nonempty static strings
with `""`. These test boolean choices and the difference between meaningful
text and empty input. Operator names are `literal_boolean` and `literal_string`;
the source name is `literal_replacement`.

Only method bodies are visited. Default arguments, arid statements, nested
definitions, empty strings, heredocs, interpolation, word/symbol lists, symbols,
regexes and command strings are unchanged. Quoted and static percent strings
are supported. The new proposals follow the earlier built-in operators; the
normal duplicate check and per-method cap still apply. Old digests and order
remain stable for unchanged subjects, but more mutants can change a run's score.
No speed, type-safety or real-fault detection improvement is claimed. See
[the literal operator rationale](docs/literal-operators.md) for fault evidence
and limits, including string encoding/frozen-value behavior.

## 🔌 Extending

Public API, stable across minor versions:

- `Saboteur::MutationSource::Base#mutations_for(subject)` returning
  `Saboteur::MutationSource::Mutation` objects made of `Edit`s (file, byte
  range, replacement). Register with `sources: [builtin, path.rb:ClassName]`.
- `Saboteur::Integration::Base` for other test frameworks (RSpec is the only one
  that ships).
- `Saboteur.hook(:before_boot | :after_boot | :before_fork | :after_fork |
  :around_mutant)` in files listed under `hooks:`.

## 🌍 Where it has run

An early release (0.3.0). Tested on the RSpec suites of plain gems
(dry-inflector, tty-color, hashie, addressable) and of two Rails 8.1 apps:
human-essentials on Postgres (4,080 mutants, 6 workers) and lobsters on SQLite,
both on macOS. Not yet tried on MySQL or older Rails versions. RSpec only, by
design. Results: [docs/validation](docs/validation).

## ⚖️ How it compares

A small, non-exhaustive comparison with [mutineer](https://github.com/davidteren/mutineer)
1.6.0 on four RSpec projects (two libraries, two Rails apps). Each configuration
ran once on sampled files, so treat the numbers as indicative. mutineer is ahead
on number of operators and CI extras, and it supports Minitest.

| Metric | saboteur | mutineer |
|---|---|---|
| Fake kills (lobsters) | 0 of 20 checked | 8 of 8 checked |
| Rails app with 6 workers | yes, same verdicts as 1 worker | 1 worker only |
| Runs on the Postgres app | yes | no |
| Time per mutant, hashie | 0.008 s | 0.092 s |
| Peak memory, hashie (summed process RSS) | 595 MB | 471 MB |
| Choice of operators, CI features | fixed set, fewer | 20 operators, baseline, HTML, GitHub Action |

Full results, method and limitations:
[benchmark page](https://vamsipavanmahesh.github.io/saboteur/benchmark/).
Scripts and raw data: [bench/vs-mutineer](bench/vs-mutineer). The memory row sums
per-process RSS, which counts shared pages more than once, and it was measured
before the fork-memory work. Read it as history, not a ranking of physical
memory.

### Memory after the fork-memory work (hashie @ 9c81e83)

Paired A/B runs against the pre-PR commit (32c0f21), 5 pairs per job level with
AB/BA alternation and cold caches, on a 2 vCPU / 2 GB shared sandbox. Peak
memory is per-process-tree PSS from /proc/smaps_rollup sampled at 0.3s. Verdict
parity: **0 verdict differences in 23,700 mutant outcomes** (1,580 mutants x 15
pairs); kill reasons (assertion vs crash class) vary run to run on both
variants, as before.

| jobs | peak PSS baseline (median, range) | peak PSS PR (median, range) | shared-memory delta |
|------|-----------------------------------|-----------------------------|---------------------|
| 1    | 101 MB (101-101)                  | 100 MB (100-102)            | ~0 (no workers to share with) |
| 2    | 133 MB (116-134)                  | 109 MB (106-121)            | -18% |
| 6    | 235 MB (192-269)                  | 196 MB (175-201)            | -17% |

Peak RSS is unchanged (median ~660 MB at jobs=6 both variants): the PR does not
touch less memory, it keeps more of it shared between workers after fork, which
is what PSS measures. On machines running many parallel workers this is the
difference that keeps the box out of swap.

Wall time on uncontended runs: 30-36s for both variants at every job level (no
regression; per-cell minimums 48s vs 49s at jobs=1, 32s vs 31s at jobs=2, 30s
vs 32s at jobs=6, PR first). The shared sandbox had multi-minute CPU-starvation
windows during this session (walls up to 594s); affected runs are flagged via
sampler cadence and excluded from wall analysis. Absolute times are specific to
this 2-core sandbox. Environment, method and the contention log are on the
[benchmark page](https://vamsipavanmahesh.github.io/saboteur/benchmark/).

## 🗺️ Where it is going

[ROADMAP.md](ROADMAP.md) lays out the plan: CI-fast runs, trusted results, a
team workflow (GitHub Action, baseline, HTML report), then 1.0. saboteur stays
RSpec-only. Design
details are in [docs/design.md](docs/design.md), prior art in
[docs/prior-art.md](docs/prior-art.md), and the project checklist in
[docs/status.md](docs/status.md).

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits need a DCO `Signed-off-by` line.

## Acknowledgements

Thanks to [Glomo](https://glomo.one) for providing the AI tokens used to build saboteur.

## License

MIT. Copyright (c) 2026 Vamsi Pavan Mahesh Gunturu. See [LICENSE](LICENSE).
