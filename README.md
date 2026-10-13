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

Declared external inputs are checked against cache and report paths using their
physical paths, including aliased parent directories. An overlap makes the run
fingerprint incomplete, so it cannot authorize cache reuse.

Internal run reports retain typed candidate-drop and cap evidence for gate
validation. These records do not change selection, scores, exit codes or the
public JSON format. Empty generation is unverified, not proof of equivalence.

The internal engine can opt in to fresh baseline evidence capture. It records
inputs before boot, planned candidate identities before scheduling and reconciled
terminal results after execution. Caps, uncovered work, invalid or empty
production, reused outcomes and changed inputs make that evidence incomplete.
The public opt-in `baseline propose`, `baseline accept` and `baseline check`
commands use this evidence to review and compare survivors. They never skip
accepted mutants or change their scores. See [Opt-in survivor baseline](#opt-in-survivor-baseline).

### The unchanged suite is checked first

Every run with selected subjects runs the loaded unchanged suite twice (the specs chosen with `--test`, if given) in fresh
supervised children before coverage lookup or incremental verdict reuse. This
costs two suite runs even on a cache hit, plus a coverage-building suite run on
a cache miss. Both baseline passes must be green, complete and in the same
RSpec order at the run seed. A failure exits 3, stops mutation and names the log and fix. Long phases
print their elapsed time about every 30 seconds, and each phase's log holds
the suite's progress and full failure detail. Each suite pass
uses `coverage_timeout` and configured memory/process limits (the suite memory
budget is four times `max_memory_mb`, as for coverage). A suite child that has
already reported its result gets up to 5 seconds to finish exiting, under the
same deadline and memory/process limits as before; if it is still running then,
saboteur stops it and keeps the result, so a slow exit is not reported as a
failure. A child that ends by itself in that window keeps its own exit status. A child killed by `SIGKILL` is called a possible
out-of-memory kill only when the process tree was seen growing toward the
memory limit. Older benchmark numbers
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
Rails app? Follow the [Rails quickstart](#rails-apps) below: the defaults are for
plain gems (`lib/**/*.rb`, `rails: false`, `jobs: 1`) and are not Rails-aware.

Start with one method. You get counts per status, a score, timing, and a
unified diff for every survivor, so you can read the exact change your tests
missed. The JSON report lands in `.saboteur/report.json`.

📋 Requirements: Ruby 3.3 or newer on Linux or macOS (it needs `fork`), and RSpec.

## 🧠 Why it is built the way it is

**It only runs tests that can matter.** Each mutant runs only the tests whose
line coverage touched the changed statement. Tests that killed earlier mutants
of the same method go first, then the fastest, and the first failure stops the
run. A change no test reaches is reported as "no coverage", not as a survivor. Endless defs (`def x = ...`) are matched to tests through per-test method call coverage, since line coverage never counts their bodies.

**It runs coarse mutants first, then fine mutants.** Each method first gets
whole-body mutants: `nil` (`true`/`false` for predicates) unless the body is empty or
only logs, and `raise` unless a catch-all rescue would absorb it. Fine-grained mutants run
regardless of the coarse verdict, including a survivor or a reused verdict.
Deleting a body unnoticed does not prove its smaller changes are harmless.
Subjects with no tests are skipped before any mutants are generated, and each
method is capped at `max_mutants_per_method` mutants (100 by default). Running
fine mutants after coarse survivors can increase run time and change scores.

**It prepares memory before it forks.** Before workers fork, saboteur warms and
compacts the Ruby heap ([`ForkReadiness`](lib/saboteur/execution/fork_readiness.rb)),
which is meant to let workers share more pages with their parent and copy less.
Observed on the pinned hashie workload (paired runs, below): about 17-18% lower peak PSS at 2 and 6 workers. Not a general guarantee.

**It is aimed at pull requests.** `--since origin/main` mutates only the methods
your branch changed: fine-grained mutants on the changed lines, plus the
whole-body mutants of those methods. On one real change in saboteur's own history, that took a file
from 139 mutants to 7, and median wall time fell 22.9% (measured at d2b7abb, before the coarse-survivor gate was removed; a rerun is pending). The time saving is
smaller than the mutant count because building the coverage map is a fixed
cost, and this is one file, not a Rails app, so it is not a general speed
claim. The full method, raw timings and
caveats are in [bench/since](bench/since/README.md).

**It checks its own kills.** After a method's mutants run, saboteur re-runs the
killing tests against the *unchanged* method. If they fail there too, the kill
is not credited and becomes an error. In one comparison on lobsters, 0 of 20
randomly sampled kills were fake. Every mutant runs in a supervised child with deadline,
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
selector; needs at least one source, unless `--since` is given - the changed
files are the sources) replaces only the files RSpec runs. Other
`rspec_args` and `.rspec` options such as `--require` stay. The coverage map
is built from only those specs, each mutant runs only the ones that cover it,
and the selection is part of the coverage and `--incremental` cache keys.

`--threshold PERCENT` (0 to 100, or `c.threshold` in `config/saboteur.rb`) is for CI.
The run exits 1 when the score is below PERCENT and 0 when it is at or above,
even with survivors. It fails closed: a run that tested no mutant has no score
and exits 1, and a run where any mutant errored or hit a resource limit exits 3,
because the score covers only part of the run. Without a threshold, any
unignored survivor exits 1. Either way, a run where more than half of the
executed mutants errored exits 3: errored mutants are outside the score,
so such a run tested almost nothing.

Other flags: `--jobs N` (concurrent workers), `--timeout-factor N`,
`--config PATH`, `--integration NAME`, `--reeval class_eval|nesting`,
`--json PATH`, `--no-cache` (rebuild the coverage map).

For pull requests, start with `--since` against your target branch. This is a
workflow recommendation, not a CLI default: plain `run` still checks the whole
configured project. To scope the specs as well, pass them with `--test` and no
source operands: `bundle exec saboteur run --since origin/main --test spec/billing_spec.rb`.
With `--since` and no `--test`, the run warns before it starts that the two baseline passes
run the loaded suite (a cold coverage cache adds one more pass), and how to
scope them. Keep whole-project runs on main: diff mode does not check every method affected by a
dependency change. [The pull-request guide](docs/pull-requests.md) covers
checkout history, a GitHub Actions example, configuration and limits.

Doctor warns when an ignore subject matches no method discovered in the included
source files. Check the exact `Class#method` or `Class.method` form and the
include/exclude settings; warnings never edit or delete ignore entries.
A malformed ignore file fails doctor with a config error before target boot.

`saboteur doctor` prints Ruby, coverage, integration, Rails/SimpleCov and boot-file
checks, then runs the unchanged suite twice with the chosen seed. It writes no
mutation reports or coverage/verdict caches. Target boot files and tests still
run, so their normal side effects remain. See the [doctor guide](docs/guides/doctor.md).

`--id` runs exactly one current mutant with its coverage-selected tests, bypassing
per-method caps, ignore suppression and incremental verdict reuse.
It still honors `--subject` and `--since` changed-line selection. See the
[replay guide](docs/guides/replay.md) for digest format, checks and limits.

Every test run starts from the same random seed (1 by default), so tests that
use `rand` see the same values in each mutant's run and in the check that
confirms a kill. The report prints the seed; pass it to `--seed` to repeat a
run.

`--incremental` reuses an earlier verdict only while the method, the whole
file it lives in, the mutant, its covering tests and their files, the lockfile
and the config are all unchanged. So a constant or helper changed in the same
file is seen. It cannot see a change in another file that the method uses (a
method it calls, a constant defined elsewhere), so run without it now and then
(and in CI on the main branch).

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
the paths with `--json` / `--html` or `c.json_report` / `c.html_report` in
`config/saboteur.rb`; set either to `nil` to turn that report off. The two paths
must differ. The HTML page shows the covered mutation score
`(killed + timeout) / (killed + survived + timeout)`, which leaves NoCoverage,
RanAtLoad and Unreachable out and keeps survivors accepted on the ignore list
in the denominator. A tool
that reads the JSON report may show a different score, because the schema counts
NoCoverage as undetected.

The score is split by how the mutant was killed. A crash kill (a `NoMethodError`,
a `TypeError`, a parse error) shows the code ran and broke, not that a test
checked a value. The terminal prints
`score 100.0 % (assertion 50.0 %, crash 50.0 %)`: each share is a part of
tested mutants, so the parts add up to the score. Timeouts and kills with no
recorded cause (a verdict reused from an older run, a test that called `exit`,
a failure outside any example) are named when there are some. Whole-body
mutants (`body_nil`, `body_true`, `body_false`, `body_raise`) are killed by
almost any test that runs the method, so a second line scores the run without
them, and shows them alone. The headline score and `--threshold` still count every
mutant. The JSON report carries both splits under `saboteur.scores`
(`all` and `withoutWholeBodyMutants`), and the HTML page prints them under
the score. The JSON also records why the run exited the way it did under
`saboteur.exitCause` (`ok`, `survivors`, `belowThreshold`,
`errorMajority`, `incompleteUnderThreshold`). In `--agent` mode the cause
follows the agent verdict, so the report and the process exit classify the
run the same way: `ok` for clean, `survivors` for survivors, and otherwise
`errorMajority` when most mutants errored or `incomplete`.

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

In diff mode (`--since`), a mutant is reported at the line where its statement
starts. A statement that spans several lines can start a line or two above the
line that changed. Under each survivor the terminal therefore prints
`changed line: path:N`, the changed line or lines (the first three) the mutant
touches, and each finding carries them as `changedLines`. Use `changedLines`,
not `line`, to put a note on a changed line of the pull-request diff. A
whole-body mutant of a method whose only change is its signature touches no
changed line and prints none.

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

`config/saboteur.rb` in the project root; CLI flags override it. Keep the shared
config usable for whole-project runs and pass `--since` in the pull-request
job. A PR-only config may set `c.since = "origin/main"`; omit `since` (or use
`c.since = nil`) in the config for audits on main. Use your actual target branch.

```ruby
Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.exclude = ["lib/my_gem/version.rb"]
  c.require = []                 # boot files, e.g. ./config/environment
  c.reeval = "nesting"           # or "class_eval"; see docs/design.md 6.1
  c.timeout_factor = 3           # per-mutant deadline = factor x its tests' recorded time
  c.timeout_min = 5
  c.max_memory_mb = 2048         # memory growth cap per mutant process tree
  c.max_processes = 64
  c.max_mutants_per_method = 100 # positive integer; raise it for a broader run
  c.ignore_file = "config/saboteur_ignore.rb"
  c.seed = 1                     # Ruby's random seed in every test run
  c.fingerprint_extra = []       # extra globs whose contents invalidate caches, e.g. ["data/*.csv"]
end
```

### Rails apps

Quickstart for a Rails + RSpec app. The defaults target a plain gem, so a Rails
app needs a few settings; the generator writes them for you.

**1. Add the gem**

```sh
bundle add saboteur --group test
```

**2. Generate the setup**

```sh
bundle exec rails generate saboteur:install
```

This writes `config/saboteur.rb`, a `bin/saboteur` binstub (it sets `RAILS_ENV=test`
for you) and a `.gitignore` entry for `.saboteur/`. It never overwrites an
existing file unless you pass `--force`, and never edits your Gemfile.

Prefer to do it by hand, or on a version without the generator? Put this in
`config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.include = ["app/**/*.rb"]
  c.require = ["./config/environment"] # boots the app
  c.rails = true                       # reconnects ActiveRecord after fork, per-worker databases
  c.jobs = 4                           # optional; the default is 1
end
```

**3. Check the setup**

```sh
bin/saboteur doctor
```

Doctor boots your app, checks the config and the test database host, and runs
your suite twice before any mutation. Fix whatever it reports first. Turn
SimpleCov off for the run if you use it.

**4. Test what your branch changed**

```sh
bin/saboteur run --since main
```

It mutates only the methods changed since `main` and reports each survivor with
its diff: a change your tests did not notice. Write a test that fails on that
diff, then run again. Use `--since origin/main` in CI. Without the generator, use
`bundle exec saboteur` and `RAILS_ENV=test` instead of `bin/saboteur`.

saboteur puts the app's `spec/` directory on the load path before
processing `require`, matching rspec, so a boot file like a dummy app's
`spec/rails_helper.rb` can require its siblings.

With `jobs` above 1 on SQLite, each extra worker gets a copy of the test
database made through SQLite's backup API, so the copy is a consistent
snapshot. A relative `database:` path resolves against `Rails.root`, the
same as Rails 7.1+ does, for the copy and for its cleanup. The copy
checkpoints the source first (`PRAGMA wal_checkpoint(TRUNCATE)`) and
refuses to run when a reader keeps the WAL busy, because copying on
would silently miss committed rows. A source file that does not exist is
an error, not a skipped copy. An in-memory SQLite database (`:memory:`) is
never copied, renamed or disconnected. After the app boots, each in-memory
database is snapshotted to a temporary file through SQLite's backup API,
and every forked child restores the snapshot into its own fresh database -
a child cannot keep the parent's connection (ActiveRecord discards
inherited pools and sqlite3 closes inherited writable handles), so without
the snapshot it would see an empty database.

For a Rails engine, point `require` at the dummy app's environment -
`test/dummy/config/environment.rb`, usually loaded for you by
`spec/rails_helper.rb`. Only a dynamically created dummy app has no
environment file; there, require the helper that calls setup instead,
such as `DummyApp.setup` in `spec/rails_helper.rb`.

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

Rails fixtures (`spec/fixtures`, `test/fixtures`), `db/structure.sql`,
`db/schema.rb` and `config/*.yml` (including `database.yml`) are part of the
cache fingerprint automatically. Use `fingerprint_extra` for any other file your
tests read.

### Load-time code, captured methods and Sorbet signatures

Code that runs while the target boots, before tests run, cannot be checked by
replacing a method later. saboteur reports these changes as `ran_at_load` rather
than survivors. Calls from test setup, including RSpec `before(:all)`, are still
checked. Load-time detection follows the `ran_at_load` idea in
[mutineer #187](https://github.com/davidteren/mutineer/pull/187).

A saved `Method` or `UnboundMethod` can keep calling the old definition after
saboteur replaces it. When tests pass without calling the replacement and a
saved method still points to the old definition, the result is `unreachable`.
A targeted execution check must also confirm the replacement was not called.
Each mutant is checked separately; one unreachable result does not skip later mutants.
The reason names the old definition's source location. A lambda that looks up
the method when it runs is still checked normally.

Coverage caches now store both per-test method hits and load-time line hits.
Older caches are rebuilt; load-time accounting preserves endless-method coverage.

One-line and endless method definitions need boot method-call counters to prove
the body ran at load; merely defining them is not execution evidence. If methods
share a physical line and any sibling is uncalled, the line is ambiguous and is
conservatively reported as no coverage, even for its called sibling.
Agent mode reports ran-at-load and unreachable work as incomplete.

A whole-suite map with only load-time hits is valid and reports load-only subjects
with their ran-at-load reason, rather than failing as an empty coverage build.
It has no mutation score when no mutant can be tested.

Both statuses are listed separately in terminal output and excluded from the
mutation score. Stryker JSON reports them as `Ignored`, with the explanation in
`statusReason`; they are not entries on your survivor ignore list.

Methods wrapped by `sorbet-runtime` signatures are checked rather than skipped
as shadowed definitions. saboteur re-evaluates the adjacent `sig` with the
changed method so the replacement keeps its signature wrapper. Missing adjacent signatures and unknown wrappers are skipped when saboteur cannot
preserve the loaded method semantics.

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

```ruby
# config/saboteur_ignore.rb
Saboteur.ignore do |i|
  i.mutation "1a2b3c4d5e6f7a8b",
             subject: "Billing::Invoice#total",
             reason: "equivalent: amounts are always whole cents"
end
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

## Argument removal

Builtin removes one ordinary positional argument from a parenthesized call.
For `Model.includes(:a, :b, c: :d)`, the two proposals remove `:a` or `:b`,
without deleting the statement or changing `c: :d`. This lets a preload check
exercise missing associations instead of only a missing return value.
The operator and source name is `argument_removal`.

Only parenthesized calls are supported in this first version. Keyword hashes,
splats, argument forwarding, bracket indexing/assignment syntax and arguments containing
heredocs are unchanged. Explicit hash arguments count as positional arguments.
Blocks and keyword pairs remain intact; separators come from Prism tokens,
so commas inside strings or comments are not mistaken for separators.
Arid statements, parameter defaults and nested definitions are skipped.

These fine proposals follow existing builtin proposals, with the same validation,
deduplication and `max_mutants_per_method` cap. Earlier digests and relative order
stay unchanged for unchanged subjects. Extra proposals can change scores or be
omitted by the cap. Removing an argument can still raise an arity error; no
non-crashing guarantee is made. The regression uses a small preload-like receiver
and checks the missing associations, not an ActiveRecord SQL benchmark. See
[the validation notes](docs/argument-removal.md) for the pinned snapshot migration.

## Hash and keyword pair removal

Builtin removes one key/value association from a hash literal or keyword list.
`Model.includes(:a, :b, c: :d)` becomes `Model.includes(:a, :b )`, so a nested
preload guard can be exercised without deleting the whole statement. A sole
hash pair becomes `{}`. Operator and source name: `pair_removal`.

Both parenthesized and command calls are supported. Splats stay intact; pairs
containing heredocs, parameter defaults, arid statements and nested definitions
are skipped. Token-based separator edits preserve comments and blocks. Nested
hash values and callable bodies are visited. Removing a required keyword can
still crash; the regression uses a preload-like receiver, not an ActiveRecord
SQL benchmark. These fine proposals follow earlier builtin proposals and use
the usual validation, deduplication, order and `max_mutants_per_method` cap.
More proposals can change scores and cap coverage. See
[the validation notes](docs/pair-removal.md) for snapshot changes.

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

An early release (0.4.0). Tested on the RSpec suites of plain gems
(dry-inflector, tty-color, hashie, addressable) and of two Rails 8.1 apps:
human-essentials on Postgres (4,080 mutants, 6 workers; the 2026-10-10 run, before
the baseline check and the coarse-gate removal) and lobsters on SQLite,
both on macOS. Not yet tried on MySQL or older Rails versions. RSpec only, by
design. Results: [docs/validation](docs/validation).

## ⚖️ How it compares

A small, non-exhaustive comparison with [mutineer](https://github.com/davidteren/mutineer)
1.6.0 on four RSpec projects (two libraries, two Rails apps). Each configuration
ran once on sampled files, so treat the numbers as indicative. The table was
measured at 2b6ec02, before the literal, filter and argument operators and
before the coarse-survivor gate was removed, so mutant counts and times will
change; a rerun is pending. mutineer is ahead
on number of operators and CI extras, and it supports Minitest.

| Metric | saboteur | mutineer |
|---|---|---|
| Fake kills (lobsters) | 0 of 20 sampled at random | 8 of 8 hand-checked (identical mutants, not a random sample) |
| Rails app with 6 workers | yes, same verdicts as 1 worker | 1 worker only |
| Runs on the Postgres app | yes | no |
| Time per mutant, hashie | 0.008 s | 0.092 s |
| Peak memory, hashie (summed process RSS) | 595 MB | 471 MB |
| Choice of operators, CI features | fixed set, fewer | 22 operators, baseline, HTML, GitHub Action |

Full results, method and limitations:
[benchmark page](https://vamsipavanmahesh.github.io/saboteur/benchmark/).
Scripts and raw data: [bench/vs-mutineer](bench/vs-mutineer). The memory row sums
per-process RSS, which counts shared pages more than once, and it was measured
before the fork-memory work. Read it as history, not a ranking of physical
memory.

### Independent review, saboteur 0.4.0 vs mutineer 1.6.0

An outside review (12 October 2026) ran both tools on the same machine and
projects. mutineer ran with its default 5 operators and with all 20. These are
the reviewer's numbers for saboteur 0.4.0, one run each. Several findings in
the right-hand column of saboteur's rows have been fixed on main since; the
rerun that replaces this table is still pending.

| Measure | saboteur 0.4.0 | mutineer 1.6.0 |
|---|---|---|
| Snippets project (11 planted gaps) | 177 mutants, 14 s, 10/11 gaps found, 9 noise survivors | Default: 56 mutants, 18 s, about 5/11. All operators: 191 mutants, 51 s, 10/11, 8 noise and duplicates |
| Dependency project (A tested only via B) | 239 mutants, 6 s | 254 mutants, 26 s (needed hand-ordered source files) |
| dry-inflector (real gem) | 551 mutants, 24 survivors, 95.6 %, 133 s | 480 mutants, 47 survivors (31 distinct), 90.1 %, 134 s |
| Test selection | Whole suite, per example, automatic | Only files passed with --test, per file |
| Kill verification | Yes (re-runs killers on unchanged code) | No |
| sorbet sig methods | Skipped at 0.4.0 | Mutated, 24/24 killed |
| Data.define / Struct.new block methods | Absent at 0.4.0 | Mutated |
| Load-time code | False survivors at 0.4.0 | ran_at_load status |
| Endless defs | Tested ones reported as no coverage at 0.4.0 | Tested ones work; untested ones show as survived |
| Order-dependent specs | Smell exposed, bogus kills rejected | Hidden (whole file runs) |
| Destructive mutant | Project wiped except .saboteur | Project wiped |
| Baseline stability | Race at 0.4.0 (13-20 % of green runs) | No failures observed (15/15) |

Not in the review and still pending: a rerun on current main, memory and
per-mutant time on the benchmark apps, and any mutineer release after 1.6.0.

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
is what PSS measures. On this workload the PSS drop is about 17-18% at 2 and 6 workers on a
2 GB sandbox. Swap was not measured.

Wall time on uncontended runs, per-cell minimums, PR first: 48s vs 49s at jobs=1, 32s vs 31s at jobs=2, 30s vs
32s at jobs=6. These are noisy per-cell minima from historical runs and do not
show a direction either way. The shared sandbox had multi-minute CPU-starvation
windows during this session (walls up to 594s); affected runs are flagged via
sampler cadence and excluded from wall analysis. Absolute times are specific to
this 2-core sandbox. Environment, method and the contention log are on the
[benchmark page](https://vamsipavanmahesh.github.io/saboteur/benchmark/).

## 🗺️ Where it is going

[ROADMAP.md](ROADMAP.md) lays out the plan: CI-fast runs, trusted results, a
team workflow (GitHub Action, baseline, HTML report), then 1.0. saboteur stays
RSpec-only. Design
details are in [docs/design.md](docs/design.md), prior art in
[docs/prior-art.md](docs/prior-art.md), and project status in
[docs/status.md](docs/status.md).

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits need a DCO `Signed-off-by` line.

## Acknowledgements

Thanks to [Glomo](https://glomo.one) for providing the AI tokens used to build saboteur.

## License

MIT. Copyright (c) 2026 Vamsi Pavan Mahesh Gunturu. See [LICENSE](LICENSE).

Internal baseline capture blocks a subject with empty generation, including a subject for which the builtin source yields no candidates. Context comparison is an extra consistency check; file fingerprint verification normally also catches source drift. Neither check proves external state stability.

### Opt-in survivor baseline

`baseline check` runs every selected mutant fresh, then compares accepted survivors. It does not skip accepted mutants, change verdicts or change scores. Use whole configured projects or `--subject` filters; diff, replay, incremental reuse and score thresholds are refused. Caps, uncovered work, empty generation, errors, resource limits, omitted malformed files, changed inputs and missing results are incomplete, even with zero survivors.

```sh
saboteur baseline propose --baseline baseline.json --proposal proposal.json
# Edit only document.accepted[*].reason in proposal.json. Give each survivor a review reason.
saboteur baseline accept --baseline baseline.json --proposal proposal.json
saboteur baseline check --baseline baseline.json
```

Proposal writes independent owner-private execution evidence under the configured cache directory. Keep that directory until acceptance; deleting it prevents acceptance. Acceptance verifies the private record and current input fingerprint before atomically publishing the manifest. For replacement, give both propose and accept `--previous SHA256`, the hash you reviewed of the current baseline bytes. Output files must not overlap project inputs or the private evidence directory. A baseline normally lives in a separate JSON file outside fixture/config input trees.

Check prints one JSON object: accepted, new, changed, resolved_kills, detected_timeouts, unmatched and errors are separate categories. Exit 0 means a compatible complete clean check; 1 needs survivor review; 2 means incompatible or invalid configuration; 3 means incomplete execution or tool failure. Propose and accept exit 0 only after their file operation succeeds. Context changes require fresh review. Timeouts remain a distinct detected category, not assertion kills.

Local evidence protects against edits to the public proposal except review reasons. It is not remote attestation, a signature, or protection against the account owner changing their private files. File fingerprints cannot prove external database, network or environment stability. `config/saboteur_ignore.rb` remains a separate legacy ignore mechanism; this gate compares every survivor regardless of ignore status.

A baseline that changes during `check` is rejected as configuration/evidence error (exit 2), not an incomplete execution result. Acceptance leaves a private `baseline.json.lock` beside the destination: keep it for cooperating-process publication locks. It contains no evidence or results. Symlinked checkout parents are normalized; symlink artifacts themselves and private-store/lock symlinks are still refused.

The builtin `endpoint_replacement` operator swaps explicit, no-argument `first`/`last` calls. It targets wrong-end/order-selection faults in collection handling. Argument-bearing slices, bare calls and block-bearing APIs are left unchanged. Receivers are not statically typed: a custom object may implement either name differently, so a crash remains a crash kill, not proof of a collection assertion.
