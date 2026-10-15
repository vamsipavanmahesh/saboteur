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

Every run with selected subjects runs the loaded unchanged suite twice (the specs chosen with `--test` if given,
otherwise the inferred specs) in fresh
supervised children before coverage lookup or incremental verdict reuse. This
costs two suite runs even on a cache hit, plus a coverage-building suite run on
a cache miss. Before the first pass, a run over the whole suite announces the example
count and the real number of full passes (a cached map only counts as
reused when it loads clean); once the first baseline pass is timed, the
run estimates the time left for the remaining baseline and coverage
passes from it - mutation time is not part of that estimate. Past 1,000
examples the announcement also names `--test` as the way to scope the run. Both baseline passes must be green, complete and in the same
RSpec order at the run seed. Set `c.baseline_passes = 1` (or `--baseline-passes 1`) for a faster PR loop: the run says so up front and gives up the order-stability comparison between passes (#55). A failure exits 3, stops mutation, prints the failing example ids and the first ten lines of the
failure inline, and names the log and fix. Long phases
print their elapsed time about every 30 seconds, with the examples finished so far, the percentage and a rough estimate of the time left (it assumes equally long examples) once the suite child has logged its first count, and each phase's log holds
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

### Hazardous calls are not mutated, and a canary watches the tree

Mutants run in your checkout, so a mutant inside a destructive call could do
real damage: a string mutation inside `FileUtils.rm_rf(File.join(Dir.pwd,
"build"))` once turned the target into the working directory itself. The
hazard guard is a syntactic filter. It recognizes destructive calls written
as direct calls: `FileUtils.rm*`/`remove_entry*` (also as bare names under
`include FileUtils`), `File.delete`/`unlink`, `Dir.rmdir`/`delete`/`unlink`,
`rmtree`, `system`/`exec`/`spawn` (bare or on `Kernel`/`Process`), backticks
and `%x`, `IO.popen`, any `Open3` method, `open` with a leading `|`, and
`send`/`public_send`/`__send__` with a literal symbol or string selector
naming one of these (dynamic selectors stay out of scope). It
suppresses any mutant that would leave such a call in place while altering
code inside it or anywhere else in the same method. A mutant that removes
every hazardous call in the method still runs, provided its replacement
introduces no new hazard. The match is by name on the written call: calls
reached through aliases, variables or other indirection are not
recognized, so the guard cannot promise to find every destructive call. The
summary reports how many mutants were suppressed. Extend or replace the list
with `c.hazard` (same tag shapes: `"FileUtils.rm_rf"`, or a bare name like
`"system"`); `--allow-hazardous` runs the suppressed mutants anyway.

Behind the guard, a canary snapshots the tracked files (or every file,
outside a repository) before mutating and probes the snapshot after every
mutant - a cheap stat pass, no tree walk. If anything vanished, the run
aborts with exit 3 and names the digest of the mutant that just ran, not
the method's last mutant. A fuller check still runs after each method. That check happens after the damage and restores
nothing; it limits how far a bad mutant gets. Recover from your own backup,
a fresh checkout or a reclone - a deleted `.git` or uncommitted work is gone
unless you have another copy. The canary is the backstop for the destructive
forms the syntactic guard cannot see.

On Linux 6.2 and later (Landlock ABI 3) each mutant child also runs under
a Landlock sandbox: the child cannot create, write, rename, unlink or
truncate files in the project tree, except `tmp/` and the
system temp dir, plus anything in `c.sandbox_writable`. The project
`tmp/` grant applies only when `tmp/` already exists - the run never
creates it for the grant - so create it before the run if your suite
writes there, or grant the directory with `c.sandbox_writable`. The cache dir
is denied too - a mutant cannot delete the baseline, the reports or
other children's logs; its own log is opened before the fork and
arrives as an inherited descriptor. Grants are additive, though: a
cache dir placed inside `tmp/`, the system temp dir or a
`c.sandbox_writable` entry stays writable, and the tool cannot deny
what another grant allows - keep the cache outside every grant for
the isolation to bite. Every other path
is denied for writing, `/dev/shm` and `/dev/tty` included; `/dev/null`
stays writable. Inherited
descriptors already open for writing outside the granted dirs are closed
before the sandbox engages - stdio redirected to a regular file and files
already deleted from the tree included (stdio on a terminal, pipe or
`/dev/null` stays), and a descriptor whose target or flags cannot be
inspected is closed too rather than trusted. A `c.sandbox_writable` grant
that contains the project root or another granted dir warns, since it
defeats or duplicates the protection; reads and process execution are
unaffected.
This DOES change what your tests can write: a suite that writes elsewhere
in the project (`db/`, `log/`, ...) fails with EACCES in mutant children -
grant that directory with `c.sandbox_writable` or opt out with
`c.sandbox = false`. Landlock covers the filesystem only - network,
sockets and IPC are never restricted - and a checkout inside the system
temp dir cannot be protected, because everything under it stays writable
so that real test suites keep working - the run warns when the effective
write set (every grant realpath'd, the system temp dir
included) contains the project root, however it happened: a checkout
inside the system temp dir, a symlinked `tmp`, or an
overlapping `c.sandbox_writable` grant. `c.sandbox = "strict"` refuses to
run at all in that situation, since the sandbox would protect nothing.
The sandbox applies to every mutant
child and fails closed: a child that cannot restrict itself reports an
error rather than run, and a kernel probe that errors (as opposed to
cleanly reporting Landlock absent) refuses the run.

On kernels from 5.13 to 6.1 (Landlock ABI 1-2) `truncate()` cannot be
restricted, so the tree is not fully read-only and the claim above does
not hold; the run notes once that children run with the guard and canary
only, exactly as on kernels without Landlock - and as on non-glibc Linux
whose C library cannot be located (musl is tried by soname first).
`c.sandbox = "strict"` turns that degraded note into a refusal;
`c.sandbox = false` opts out.


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
Minitest is not supported; see [Minitest](docs/minitest.md) for why and what it would take.

## 🧠 Why it is built the way it is

**It only runs tests that can matter.** Each mutant runs only the tests whose
line coverage touched the changed statement. Tests that killed earlier mutants
of the same method go first, then the fastest, and the first failure stops the
run. A change no test reaches is reported as "no coverage", not as a survivor. Branch coverage separates arms on the same line: an edit inside an arm no test took reports "no coverage (branch not taken)". Ruby does not expose `&&`/`||` right operands as branches, so those keep line-based selection. `case/in` pattern edits use the enclosing case and clause execution lines; edits in an untested clause body still stay uncovered. Whole-body replacements use every test of the method, including methods that start with a heredoc. Endless defs (`def x = ...`) are matched to tests through per-test method call coverage, since line coverage never counts their bodies. Methods defined inside blocks (`Class.new do`, `Data.define do`, `included do`) are not mutated yet; the run lists them as skipped, "defined inside a block".

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
bundle exec saboteur doctor                       # environment checks only
bundle exec saboteur doctor --suite --seed 42     # plus two unchanged suite checks
bundle exec saboteur run --since origin/main      # methods changed on this branch
bundle exec saboteur run --subject 'Billing::Invoice#total'
bundle exec saboteur run --subject Billing        # a namespace
bundle exec saboteur run --incremental            # reuse verdicts whose inputs did not change
bundle exec saboteur run --seed 1234              # repeat a run that used seed 1234
bundle exec saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb --test spec/b_spec.rb
bundle exec saboteur run --threshold 90           # exit 1 when the score is below 90 %
bundle exec saboteur run --id DIGEST --seed 1234  # replay one full current mutant digest
bundle exec saboteur run --fail-fast              # stop after the first subject with a survivor
bundle exec saboteur run --matrix                 # every covering test per mutant: blind and redundant tests
bundle exec saboteur run --verbose --no-color     # add score split, timings and kill causes; no colour
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

`--max-timeouts N` and `--max-errors N` (or `c.max_timeouts` / `c.max_errors`)
are two more CI gates. Each takes a count or a percentage of the executed
mutants (`--max-errors 5%`). The run exits 1 when the count (or share) is
above the limit, with `exitCause` `maxTimeouts` or `maxErrors` in the JSON report.
`--threshold` already compares the covered score, `(killed + timeout) /
(killed + survived + timeout)`, so no separate score flag exists. With
`--max-errors`, errored mutants are judged by that limit instead of making a
`--threshold` run exit 3. Survivors and a score below the threshold keep
their own causes when they fail too. The gates cannot be combined with `--agent`.
The GitHub Action has no input for them yet.

Other flags: `--jobs N` (concurrent workers), `--timeout-factor N`, `--baseline-passes N`, `--max-duration DUR`,
`--config PATH`, `--integration NAME`, `--reeval class_eval|nesting`,
`--json PATH`, `--no-cache` (rebuild the coverage map), `--allow-focus`.

Two presets bundle the common loops (#244): `saboteur pr [REF]` is the pull-request loop - `--since REF` (default `main`), one baseline check and a ten-minute `--max-duration` that opts out of the budget-specific exit 4 (normal and incomplete verdicts still fail the run); `saboteur audit` is the whole project: `--all`, all operators, both baseline checks and both reports (an explicit `--test` replaces the injected `--all`; configured selection limits such as `since`, subjects, exclusions and a configured budget still apply). The run prints the expansion up front, and an explicit flag after the preset wins.

A stray `fit`, `fdescribe` or `:focus` example, with `filter_run_when_matching :focus`, makes RSpec skip
every other example. The baseline stays green and the score would cover only the focused ones, so
saboteur exits 2 and names the focused examples. Remove the focus, or pass `--allow-focus` (config
`c.allow_focus = true`) to run the narrowed suite. Filters you name in `rspec_args` or `.rspec`, such
as `--tag slow`, and example selectors such as `--test spec/a_spec.rb:12`, are on purpose and are not refused. The
check compares what RSpec runs with what it would run without the stray focus, so examples RSpec leaves out anyway
(`:if` / `:unless`, `--tag`, exclusions, selectors in another file) never count as hidden.

For pull requests, start with `--since` against your target branch. This is a
workflow recommendation, not a CLI default: plain `run` still checks the whole
configured project. To scope the specs yourself, pass them with `--test` and no
source operands: `bundle exec saboteur run --since origin/main --test spec/billing_spec.rb`.
A changed Ruby file whose changed lines cover no method mutates nothing; the run
warns and names the file instead of silently selecting zero subjects. Comment-only
or formatting-only changes within discovered methods are skipped without this
warning; the run reports those skipped methods. A changed Ruby file that an
include pattern covers but `c.exclude` removes mutates nothing either, and the
run warns and names up to five such files - narrow or remove the `c.exclude`
entry, or pass the file as a positional source operand (configured excludes are
then ignored). `--subject` cannot help here: it filters subjects inside the
files left after excludes.

Without `--test`, the run infers the specs: the spec named after each mutated
file (`lib/a/b.rb` runs `spec/a/b_spec.rb`; `app/` files and `spec/lib/` work
too) runs for the baseline passes, the coverage pass and every mutant, as
`--test` would. With `--since` only the changed files count; without it every
included file does. It is a naming guess, not coverage: a spec that reaches the
mutated file only through another file does not run, so a mutant only that
spec would kill can survive, and a line none of the inferred specs executes is
reported as NoCoverage. A file needs no inferred spec when it has no mutation
subjects (with `--since`: none on its changed lines), such as a comment-only
change within a method or a deletion leaving only blank/comment context; the
run says so and skips those files. When no file has a mutation subject at all,
the run reports that there is nothing to mutate. A `--subject` run infers only
from the named subjects' files: an unrelated spec-less file never stops a
one-method run, and a subject file with no conventional spec stops the run
like any other unmatched file. With `--since` only named subjects on changed
lines count: an unchanged subject file, one whose changes sit in other
methods, or one with a comment-only change is skipped, not stopped.

A file that needs a spec and has none stops the run before it boots (exit 2)
and names both ways out: `--test` with the specs to run, or `--all` for the
whole suite. An unmatched file no longer silently narrows the selected source
scope or widens the test run to the whole suite. Whole-project audits should
use `--all` explicitly. The agent JSON records the inferred specs as its
`tests`, so its follow-up commands keep the same scope.

`--all` (config `c.test_selection = :all`) runs the whole configured suite.
With `--since` or `--all` and no inferred or named specs, the run warns before
it starts that the two baseline passes run the loaded suite (a cold coverage
cache adds one more pass). `--guess-tests` is a deprecated alias for the
default inference and `--no-guess-tests` warns and is ignored; use `--all` for
the whole suite. `--all` cannot be combined with `--test` or `--guess-tests`,
and `--guess-tests` cannot be combined with `--test`. Keep whole-project runs
on main: diff mode does not check every method affected by a dependency change.
[The pull-request guide](docs/pull-requests.md) covers
checkout history, a GitHub Actions example, configuration and limits.

Doctor warns when an ignore subject matches no method discovered in the included
source files. Check the exact `Class#method` or `Class.method` form and the
include/exclude settings; warnings never edit or delete ignore entries.
A malformed ignore file fails doctor with a config error before target boot.

`saboteur doctor` prints Ruby, coverage, integration, Rails/SimpleCov and boot-file
checks. Add `--suite` to also run the unchanged suite twice with the chosen seed
(`--test PATH`, repeatable, limits those runs to some specs and implies `--suite`),
since that takes hours on a large suite. It writes no
mutation reports or coverage/verdict caches. Target boot files and tests still
run, so their normal side effects remain. See the [doctor guide](docs/guides/doctor.md).

`--id` runs exactly one current mutant with its coverage-selected tests, bypassing
per-method caps, ignore suppression and incremental verdict reuse.
It still honors `--subject` and `--since` changed-line selection, and the
hazard guard: a digest that names a suppressed mutant is refused unless
`--allow-hazardous` is also given. See the
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

Output: survivors first, then a short summary last, so the summary stays on
screen. Survivors are grouped by file, then method, then line. Each line is
printed once as `path:line in Subject`, with the source line and the tests that
covered it, then one compact line per mutation: `operator original -> replacement digest`,
and a hint on what kind of test would kill it. The summary has the counts per
status, the score, a table of scores per file (worst first) and a one-line
legend. When survivors remain, the Next steps footer prints the complete
replay command - ref, subjects, specs, sources, seed and the run settings
the agent protocol records, including the CLI-only switches that change
candidate availability or boot (`--allow-hazardous`, `--allow-focus`) -
shell-escaped and printed in full however long it gets, so running it
as-is replays the survivor with the same selection. Framework and
generation settings from the config file (arid/hazard patterns,
whole-file, require, rspec_args, rails) ride along through the command's
`--config` or the default config path. Only knobs that cannot change a
by-digest replay (`--max-mutants-per-method`, `--fail-fast`,
`--threshold`) are left out. The agent protocol instead omits a command
longer than 1024 bytes, and the agent rebuilds it from the run's
provenance. `--verbose` adds the score split, mean time, whole-body score and
kill causes, and prints one line per finished subject with its result
marks, so a survivor is attributable to a method before the run ends. Colour is on when stdout is a terminal and `NO_COLOR` is not set;
`--color` and `--no-color` override that. While mutants run, stderr shows
`done/total (percent) eta`: a live counter on a terminal, and dots with a
counter every 50 mutants otherwise. Skipped and reused mutants are not
counted, so the count can end below the total.
The tests that covered the survivor's line and
still passed with the mutant applied are listed (the first five, likeliest killers
first; the rest are under `coveredBy` in the JSON report). The missing
check may belong in one of them. Line coverage can overstate which tests
exercise a line, so treat the list as a lead. A survivor reused with
`--incremental` was not run again, and the list says its tests passed in an
earlier run. `--fail-fast` (serial runs only) stops after the first subject
that has a survivor the ignore list does not accept. The report then covers
only the subjects that ran: the terminal says which subjects did not run, the
JSON report has an `earlyStop` field naming them (`exitCause` is `failFast`),
`--agent` reports status `partial` with the reason `fail_fast`, and the run
always exits 1, so no `--threshold` can pass it. It cannot be used with
`baseline` evidence. Survivors that share a line are printed together only
when their covering tests, reuse status and changed lines are identical;
otherwise each distinct set of evidence is printed above its own mutations.
Hints are suggestions, not diagnoses: a survivor can also be an equivalent
mutant. The HTML page shows the same list in the
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

`--matrix` runs every covering test against every mutant instead of stopping at
the first failing one, so a killed mutant lists all of its killers. After the
survivors the report prints two lists: blind tests (they covered mutants and
killed none) and redundant tests (they killed some, and every one of those
mutants had another killer). The run is slower, by up to the number of covering
tests per mutant. `--matrix` cannot be combined with `--incremental`, because a
reused verdict lists only the first killer. A redundant test is a lead, not a
verdict: it may guard behavior no selected mutant touches. A selection with
`--since` or `--subject` describes only the selected methods.

[Scores](docs/scores.md) defines each number on this page: the covered score, the
score a Stryker dashboard shows, the assertion and crash split, and what makes a run
incomplete.

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

New to survivors? The [reading survivors guide](docs/guides/reading-survivors.md) walks one from the diff to the test that kills it.

Exit codes: 0 no survivors (or all on the ignore list), or the score
meets `--threshold`; 1 survivors, or the score is below `--threshold` or
missing; 2 bad configuration or a missing source or test; 3 the tool
failed (with `--threshold`, also any errored or resource-limited
mutant). Unexpected `StandardError` or `LoadError` failures print
`saboteur: internal error (...) - please report it` and exit 3, rather
than dying with a bare stack trace and an accidental exit code. The full
backtrace lands in `<cache_dir>/internal-error.log` (default
`.saboteur/`), and `--verbose` also prints it to stderr. The message
names the log only after a successful write: an unset `cache_dir` or an
unwritable directory leaves the one-liner standing alone. The executable
loads the crash reporter before the CLI, so a failure while it is
loading, being built, or parsing arguments gets the same report;
failures earlier than that - coverage setup or the reporter's own load -
get only the bare one-liner and still exit 3. Once the crash
reporter has loaded, agent mode reports the same failure as agent
JSON, using a standalone payload if the agent reporter has not
loaded. Before the crash reporter loads, only the one-line
diagnostic and exit 3 are available.
`--max-duration 10m` budgets the whole run, baselines included: the budget is checked before every subject and between mutants inside one, so past the budget the run finishes only the mutant in flight (bounded by its timeout), then stops before the next subject. Admitted phases (baseline checks, the coverage map build) are capped at the time left, as are verdict checks and timeout calibrations; a kill or timeout the budget leaves uncheckable is reported as `unverified` - outside the score, never cached, listed under the early stop - instead of becoming an error, reports which selected subjects never ran and which mutants were omitted, marks the JSON and agent output partial (`earlyStop.reason: "max_duration"`), and exits 4; `--max-duration-ok` (or `c.max_duration_ok = true`) leaves the exit to the plain verdict instead, which can still fail the run - 1 on survivors, 3 when the budget stopped the run before any mutant was tested. In agent mode the exit code stays verdict-driven and the budget shows up in `incomplete[]` and `earlyStop` (#245).

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
  c.whole_file = []              # subject ids or globs to re-evaluate as a whole file (see below)
  c.reeval = "nesting"           # or "class_eval"; see docs/design.md 6.1
  c.timeout_factor = 3           # per-mutant deadline = factor x its tests' recorded time
  c.timeout_min = 5
  c.max_memory_mb = 2048         # memory growth cap per mutant process tree
  c.max_processes = 64
  c.max_mutants_per_method = 100 # positive integer; raise it for a broader run
  c.hazard = Saboteur::MutationSource::HazardGuard::DEFAULT_HAZARD # calls whose arguments are never mutated
  c.sandbox = true               # read-only project tree for mutant children (Linux 6.2+); "strict" refuses to run degraded
  c.sandbox_writable = []        # extra dirs mutant children may write, e.g. ["db", "log"]
  c.ignore_file = "config/saboteur_ignore.rb"
  c.seed = 1                     # Ruby's random seed in every test run
  c.baseline_passes = 2          # unchanged-suite checks before mutating; 1 skips the order-stability check (#55)
  c.max_duration = nil           # wall-clock budget in seconds, e.g. 600; an exhausted budget exits 4 (#245)
  c.max_duration_ok = false        # true: an exhausted budget does not fail the run
  c.allow_focus = false          # true runs a suite narrowed by fit/fdescribe/:focus instead of exit 2
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

The database check refuses any test database whose host is not local
(`localhost`, `127.0.0.1`, `::1`, `0.0.0.0` or a socket), so a remote
database is never mutated by accident. `0.0.0.0` counts as local: compose
setups write it into database URLs, and connecting to it reaches this
machine. For another disposable test database host, assert it yourself:
`c.allow_db_hosts = ["db.internal"]` in `config/saboteur.rb`.

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

### Whole-file re-evaluation (opt-in)

Surgical re-evaluation refuses a method whose owner it cannot resolve or whose
loaded definition is not the one in the file. The skip reason ends with a hint.
List such subjects in `c.whole_file` (ids or globs such as `"Point#distance"` or
`"Geometry::*"`) and the child evaluates the whole mutated file instead. This
applies to methods saboteur already finds as subjects; it does not make new
kinds of definitions selectable (methods inside `Data.define` or `Struct.new`
blocks are still not found). The file's top-level code then runs again in every
child, after the run's seed is set: load-time side effects repeat and constants
it assigns are rebuilt, with redefinition warnings silenced. If a later
definition in the same file replaces the mutated method, the mutant could never
run, so a survivor there is reported as unreachable instead. It is off by
default, and the cache key includes the list.
Signature text alone does not remove mutants. `body_nil` and last-statement
removal remain available even when `sig` declares a non-nil return type.
`checked(:never)`, unchecked `checked(:tests)` signatures, configured default
levels, custom validation handlers and wrapper shims can all allow nil to
reach real assertions. saboteur does not verify enforcement, evaluate return
type expressions or infer types from constant names. Aliases, enclosing
namespace constants and transformed generic types therefore cannot change
mutation generation. RBS signatures are not read yet. Type-only crash kills
remain visible in the crash share, not silently pruned.

The Sorbet E2E fixture is a wrapper/registry shim without runtime type checking.
It tests re-evaluation and assertion detection, not real Sorbet enforcement or
proof of type-check noise reduction.

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

### Threads alive at fork time

Threads do not survive `fork`, so a run names any that are alive when the
workers fork. Two are well known:

- `AR Pool Reaper` only maintains the parent's connection pool. It is
  expected harmless when children reconnect the database after fork -
  saboteur's rails mode does exactly that. Without verified
  reconnection, do not assume the inherited connection state is safe.
- `DEBUGGER__::SESSION@server` is the debug gem's remote console. What
  it does in children depends on `RUBY_DEBUG_FORK_MODE`: with `parent`
  no debugger runs in children; with `child` or `both` (the gem's
  default) the debugger activates in children and can pause or
  interfere with supervised mutation runs. For unattended runs, do not
  start the remote debugger at all: drop `RUBY_DEBUG_OPEN` or require
  `debug` without `:open`.

Any other thread gets a generic caveat: a thread that does not run in a
child cannot do background work a mutant's test may rely on, so results
can differ when one is left behind.

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

## Chain removal

Builtin drops one link from the middle of a dotted method chain: `user.name.strip`
becomes `user.strip`, and `a.b.c.d` gives `a.c.d` and `a.b.d`. The first receiver
and the last call stay, so a test has to notice that a step in between went
missing. The link goes whole, with its arguments and block. The operator and
source name is `chain_removal`.

Operators, index calls and bare-name receivers are not chains and are unchanged.
The target of a write (`user.account.profile.name = 1`, `+=`, `||=`, `a.b[0] = 1`)
is left whole: no link of its receiver chain is dropped, however long. Only
the value on the right can be mutated. `freeze`, `dup`, `clone`, `itself`
and `tap` links are never removed. Tests can observe frozenness, copies and a
`tap` block's effects, but those are other contracts than a missing step in a
query chain, and dropping such a link mostly yields noise, so this operator
leaves them out. Arid statements and nested definitions are skipped.

If you confirm the shorter chain is equivalent across the intended
inputs (for example a duplicated column), simplify the code or ignore
the mutant.

Chain removal is on by default, like `argument_removal` and `pair_removal`.
Its proposals follow the other fine proposals, with the same validation,
deduplication and `max_mutants_per_method` cap.

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
  :around_mutant)` in files listed under `hooks:`. An extensionless hooks
  path resolves its `.rb`, the way `require` does.

## 🌍 Where it has run

Tested on the RSpec suites of plain gems
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

A private consultant review ("saboteur 0.4.0 - Deep Review", 12 October 2026,
not published) ran saboteur 0.4.0 at 38b1834 and mutineer 1.6.0 at a766c96 on
the same machine and projects: Linux x86_64, 1 vCPU, 4 GB, Ruby 3.4.5, Prism
1.2.0, RSpec 3.13, no Rails or sqlite3. mutineer ran with its default 5
operators and with all 20. The project and timing rows are one run each. The
rows describe saboteur at 38b1834; several of its findings have been fixed on
main since. The rerun that replaces this table is still pending.

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
| Baseline stability | Race at 0.4.0: 4 of 30 green runs failed (13 %), 5 of 25 under CPU contention (20 %) | No failures observed (15/15) |

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

Before you ask for review, run the local preflight check on your exact head:

```sh
ruby script/preflight --base <full main sha> --head <full head sha> --base-ref main --mode full
```

It runs scope, sign-off, SPDX, full RuboCop and the specs, and writes a report under `tmp/preflight/`. A pass is not an approval; fast mode is partial. See [docs/preflight.md](docs/preflight.md).

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

Score-drop gate: `saboteur baseline check --baseline baseline.json --epsilon POINTS` also fails (exit 1,
state `review_required`) when the fresh score is more than POINTS percentage points below the score recorded in
the baseline. Both scores use saboteur's own formula, (killed + timeout) / (killed + timeout + survived), over
every candidate. The baseline already stores each candidate's status, so no new file format is needed. This
catches what the survivor comparison cannot: a score that falls because killed mutants disappeared (deleted or
rewritten code) while every accepted survivor is still matched. A drop of exactly POINTS passes; a rise never
fails. The check prints a `score` object (`baseline`, `current`, `drop`, `epsilon`, `exceeded`) only when
`--epsilon` is given. Without it, behavior is unchanged. POINTS is 0 to 100. It lives on `baseline check`,
not on `run`: the delta gate needs the baseline's fresh whole-scope evidence, which `run` does not produce.
It is not the same as `--threshold`, which gates an absolute score.

In GitHub Actions, the action's `baseline` and `baseline-epsilon` inputs run this check; see
[docs/github-action.md](docs/github-action.md).

Local evidence protects against edits to the public proposal except review reasons. It is not remote attestation, a signature, or protection against the account owner changing their private files. File fingerprints cannot prove external database, network or environment stability. `config/saboteur_ignore.rb` remains a separate legacy ignore mechanism; this gate compares every survivor regardless of ignore status.

A baseline that changes during `check` is rejected as configuration/evidence error (exit 2), not an incomplete execution result. Acceptance leaves a private `baseline.json.lock` beside the destination: keep it for cooperating-process publication locks. It contains no evidence or results. Symlinked checkout parents are normalized; symlink artifacts themselves and private-store/lock symlinks are still refused.

The builtin `endpoint_replacement` operator swaps explicit, no-argument `first`/`last` calls. It targets wrong-end/order-selection faults in collection handling. Argument-bearing slices, bare calls and block-bearing APIs are left unchanged. Receivers are not statically typed: a custom object may implement either name differently, so a crash remains a crash kill, not proof of a collection assertion.

JSON findings are ordered by a deterministic [review ranking](docs/survivor-ranking.md): coarse first, then covering-test count, edited-line impact and changed-line proximity, with file/line/digest ties. The terminal groups survivors by file, method and line first; the ranking only orders the survivors on one line, and every survivor is listed, in review mode too. Only consecutive survivors with matching evidence share a test/evidence block; repeated evidence after another group is printed again to keep that order. Ranking does not change scores or execution.

Cache and baseline identities include the policy. Re-propose and review old survivor baselines with `baseline propose`; never auto-accept new survivors. Mutation digests for unchanged edits stay stable.

### Preview and choose operators

`bundle exec saboteur run --dry-run` discovers source methods and generates candidates without booting the app, running tests, forking, or writing reports/caches. It honors `--since`, `--subject` and source arguments. It prints per-method counts and cap omissions. After a matching normal run, a cached estimate shows baseline covering-test work (cached original-test durations times planned mutants; it is not a bound on mutant runtime and excludes boot and fork costs). If any file cannot be parsed, the total is marked INCOMPLETE and no estimate is given.

Trust boundary: `--dry-run` never boots the app or runs its tests, but custom `sources` entries (`path.rb:ClassName`) are still `require`d to generate candidates, so their code runs. Only preview with sources you trust.

`bundle exec saboteur run --list-operators` lists every builtin name and description. All builtin operators run by default, including [`range`](docs/operators/range.md), [`operator_assignment`](docs/operators/operator_assignment.md), [`condition_negation`](docs/operators/condition_negation.md), [`method_swap`](docs/operators/method_swap.md), [`operand_replacement`](docs/operators/operand_replacement.md), and [`interpolation_removal`](docs/operators/interpolation_removal.md). `--operators arithmetic,comparison` or `c.operators = ["arithmetic", "comparison"]` still selects a subset; `all` selects every name. There is no opt-in tier. `--exclude-operators range,condition_negation` or `c.exclude_operators = ["range", "condition_negation"]` removes named operators from that selection; exclusion wins if a name is in both lists. An empty selection means all, while an empty exclusion means none. CLI lists replace their corresponding config lists. These controls apply to builtin operators, not custom source plugins. Selection and exclusions invalidate cached verdict identity and are carried into agent rerun/replay commands.


All operators run unless you select a smaller set; exclusions always remove operators from that set.
Repeated `--operators` or `--exclude-operators` flags use the last list, not a union.
To re-enable an operator excluded in config: `bundle exec saboteur run --operators range --exclude-operators ''`.
To keep the 0.5.0 default inventory: `bundle exec saboteur run --exclude-operators range,operator_assignment,condition_negation`.
The old `core` and `extended` names now give a migration error, not a changed selection in disguise.
An empty effective selection is a usage error before boot. `--list-operators` loads current config and shows on/off plus examples; preview and the run header show the effective set.

```ruby
Saboteur.configure do |c|
  c.operators = [] # all by default; or ["arithmetic", "range"] for a subset
  c.exclude_operators = ["condition_negation"]
end
```

Inspired by mutineer's --dry-run, --list-operators and --operators tiers (github.com/davidteren/mutineer, MIT, by David Teren).

### Agent survivor hints and score history

`--agent` findings include operator-specific `hint` suggestions and a shared
`hintCaveat`. Hints do not diagnose a missing test or assertion; equivalent
mutants and limited observation are still possible. Unknown operators have no
hint unless marked coarse. The normal JSON byte budget still applies.

Use `--score-history PATH` (or `c.score_history = PATH` in your config) to append
one score-history JSONL record per finished report. History is off by default;
changes are printed to stderr, not agent stdout. See [score definitions and
history limits](docs/scores.md). The file can be uploaded by your own artifact
step; the bundled Action's upload behavior is unchanged.

Score history now refuses non-regular files, symlink paths and report/history
inode aliases before running the engine or writing reports. Imported records
have a 64 KiB per-line bound and strict validation of supported version 1
and version 2 records, including counts, scores and duplicate keys. History is an output, excluded from baseline
fingerprints. See [history safety and comparison limits](docs/scores.md).

Operator policy version 2, selected names, excluded names and effective names are in JSON/agent/baseline evidence and fresh score-history v2 rows. Old history v1 rows remain readable but are not compared across policy versions.
### Inline suppression comments

`total = a + b # saboteur:disable-line arithmetic reason="rounding checked elsewhere"` suppresses edits starting on that line, restricted to the named operators. Omit names to suppress all operators. Multiple names are space-separated. Only actual Ruby comments count; directive text in strings does not. A missing or blank reason or unknown operator is a usage error naming file:line. Terminal, JSON and HTML list every suppressed candidate with its reason and digest, outside the score. Moving the commented code keeps the suppression. Multi-line edits use their starting line.

Inspired by mutineer's inline suppression comments (github.com/davidteren/mutineer, MIT, by David Teren).

Inline suppressions bound completeness: classic scores still exclude suppressed candidates, but baseline evidence is incomplete when any inline candidate is suppressed. Agent output reports `inline_suppressed` with its count and points to the full audit. Reasons are audited, not proof that suppressed work was checked.

Source-only `--dry-run` lists the suppressed count and each audit row in selected methods, before diff restriction and the per-method cap. They are outside the planned total. Preview still does not boot the app or write reports.
