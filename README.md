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
# Install the gem:
gem install saboteur

# Or add it to the Gemfile:
bundle add saboteur --group test

# Either way:
bundle exec saboteur run
```

The first run builds a coverage map of which tests touch which code. The
map is cached and reused while your code and tests stay unchanged, so
later runs start fast.

On a branch, `bundle exec saboteur pr` mutates only the methods you
changed relative to `main`, with one baseline pass and a ten-minute
budget. Pass `--since` for a different base, for example
`bundle exec saboteur pr --since master`.

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
  and process-count limits on every mutant in the default in-process
  mode; a Landlock sandbox on Linux
  6.2 and newer.
- **Extension points.** Add your own mutation operators through the
  public interface.

## Honest limits

- saboteur is RSpec-only and needs `fork`; there is no Windows or Minitest
  support today.
- A survivor is review evidence, not automatic proof of a bug in your tests.
- Diff and incremental modes are iteration aids; run the whole project without
  them on main or before a release.
- The hazard guard is syntactic, the sandbox varies by platform, and network
  access is never restricted. Stub real APIs and use a container when needed.

## Run model, safety and evidence

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

### Safety guardrails

| Layer | What it does | What it does not do |
| --- | --- | --- |
| Baseline | Runs the unchanged suite before mutation. | Does not prove a suite is free of flaky tests. |
| Hazard guard | Suppresses mutants in known destructive call forms. | Is syntactic; aliases, variables and dynamic selectors can escape it. |
| Canary | Aborts the run when tracked files disappear after a mutant. | Detects damage after it starts; it restores nothing. |
| Landlock | When available on Linux 6.2+, makes the project tree read-only to mutant children. | Is Linux-only and covers the filesystem only; network is never restricted. |

#### The unchanged suite is checked first

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
[baseline stability](docs/baseline-stability.md) for limits and hook behavior.

#### Hazardous calls are not mutated, and a canary watches the tree

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

#### Platform support

| Platform | Mutant-child filesystem protection | Effective guard |
| --- | --- | --- |
| Linux 6.2+ (Landlock ABI 3) | Available; doctor confirms the probe. Read-only project tree, except explicit grants. | Landlock + hazard guard + canary. |
| Linux 5.13-6.1 (Landlock ABI 1-2) | No sandbox: `truncate()` cannot be restricted. | Hazard guard + canary. |
| Other supported Linux | No usable Landlock. | Hazard guard + canary. |
| macOS | No sandbox; Landlock is Linux-only. | Hazard guard + canary. |

Network access is never restricted on any platform: a mutant can reach real
APIs if a test is not stubbed. When a mutant could write outside the project,
run saboteur in a container; when it could reach real APIs, deny the network
or stub the APIs. `saboteur doctor` probes and reports what your platform
actually allows.


<a id="why-it-is-built-the-way-it-is"></a>
## 🧠 Why it is built the way it is

**It only runs tests that can matter.** Each mutant runs only the tests whose
line coverage touched the changed statement. Tests that killed earlier mutants
of the same method go first, then the fastest, and the first failure stops the
run. A change no test reaches is reported as "no coverage", not as a survivor. Branch coverage separates arms on the same line: an edit inside an arm no test took reports "no coverage (branch not taken)". Ruby does not expose `&&`/`||` right operands as branches, so those keep line-based selection. `case/in` pattern edits use the enclosing case and clause execution lines; edits in an untested clause body still stay uncovered. Whole-body replacements use every test of the method, including methods that start with a heredoc. Endless defs (`def x = ...`) are matched to tests through per-test method call coverage, since line coverage never counts their bodies. On main, methods defined by the four core class factories (`X = Data.define(...)`, `Struct.new`, `Class.new`, `Module.new` with a block) and literal-name `define_method(:name) { ... }` calls are ordinary mutation subjects, not skipped; those cases are unreleased and not in v0.7.0. Defs inside non-factory blocks still get the "defined inside a block" skip reason.

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
whole-body mutants of those methods. On one real change in saboteur's own
history, that took a file from 139 mutants to 7. The time saving is smaller
than the mutant count because building the coverage map is a fixed cost, and
this is one file, not a Rails app, so it is not a general speed claim. The
measured numbers, the harness that reproduces them, raw timings and caveats
are in [bench/since](bench/since/README.md).

**It checks its own kills.** After a method's mutants run, saboteur re-runs the
killing tests against the *unchanged* method. If they fail there too, the kill
is not credited and becomes an error. In one comparison on lobsters, 0 of 20
randomly sampled kills were fake. Every mutant runs in a supervised child
with deadline, memory and process limits, and saboteur tracks and kills the
processes it starts. On Linux, each child also carries a unique marker in
its environment and process name; when a test daemonizes through `setsid`
and its intermediate parent exits between polls, the end-of-run kill sweeps
the process table for that marker. The sweep is Linux-only, and a daemon
that renames itself can still escape it, so the inherited CPU limit stays
the backstop.

**It is open.** The report is JSON in the Stryker mutation-testing-report
schema, and you can add your own mutants through a small public interface.
The main branch documents a stability policy for the agent JSON format and
exit codes: [docs/stability](docs/stability.md). That policy is unreleased on
main and is not part of v0.7.0.

<a id="usage"></a>
## 🛠️ Usage

### Choose a run

| I want to... | Command | Notes |
| --- | --- | --- |
| Check the setup | `bundle exec saboteur doctor` | No mutation run, reports or caches. |
| Try one method | `bundle exec saboteur run --subject 'Billing::Invoice#total'` | Best first run. |
| Review a pull request | `bundle exec saboteur pr origin/main` | Preset: changed methods, one baseline pass, 10-minute budget. |
| Set the diff scope yourself | `bundle exec saboteur run --since origin/main` | Mutates methods changed since the ref; on main, supported constants too (not in v0.7.0). |
| Audit the whole project | `bundle exec saboteur audit` | Whole scope, all operators, both baseline checks and both reports. |
| Choose files and specs | `bundle exec saboteur run lib/a.rb --test spec/a_spec.rb` | Sources and test selection are explicit. |
| Iterate locally | `bundle exec saboteur run --incremental` | Reuses verdicts whose recorded inputs are unchanged; see the limits below. |
| Repeat a run | `bundle exec saboteur run --seed 1234` | Use the seed printed by the earlier run. |
| Replay one mutant | `bundle exec saboteur run --id DIGEST --seed 1234` | Uses the full current digest. |
| Gate CI on score | `bundle exec saboteur run --threshold 90` | Exits 1 below 90%; incomplete runs still fail closed. |
| Inspect test quality | `bundle exec saboteur run --matrix` | Runs every covering test to find blind and redundant tests. |
| Preview the work | `bundle exec saboteur run --dry-run` | Discovers subjects and mutants without booting the app. |
| List operators | `bundle exec saboteur run --list-operators` | Shows the effective operator policy. |
| Stop early | `bundle exec saboteur run --fail-fast` | Serial runs only; always exits 1 when it stops. |
| Add detail | `bundle exec saboteur run --verbose --no-color` | Score split, timings, kill causes and no color. |

### Sources, specs and gates

Positional operands name the sources to mutate: Ruby files, or directories
(all their `.rb` files). Each must exist; a typo or a non-Ruby file exits 2
before anything runs. They replace `include` and `exclude`. `--test`
(repeatable; spec files or directories, with an optional `:LINE` or `[1:2]`
selector; needs at least one source, unless `--since` is given - the changed
files are the sources) replaces only the files RSpec runs. Other
`rspec_args` and `.rspec` options such as `--require` stay. When neither
`rspec_args` nor `.rspec` names a file or directory to run, saboteur runs the
default path (`--default-path` from `.rspec`, else `spec`), as the `rspec`
command does. That default-path fallback is unreleased on main; v0.7.0 needs
an explicit file or directory when RSpec's parse finds none. The coverage map
is built from only those specs, each mutant runs only the ones that cover it,
and the selection is part of the coverage and `--incremental` cache keys.

**Unreleased on main:** each `--test` takes one spec path; repeat the flag
for several specs. A spec file passed as a positional source exits 2 with a
message telling you to repeat `--test`. Spec files in `--since` scope are
never mutated; when every subjectless changed file is a spec, the warning
says so and points back to `--test`.

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
The GitHub Action has no dedicated inputs for them yet; pass them through its
`arguments` input.

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

### Pull requests and inferred specs

For pull requests, start with `--since` against your target branch. This is a
workflow recommendation, not a CLI default: plain `run` still checks the whole
configured project. To scope the specs yourself, pass them with `--test` and no
source operands: `bundle exec saboteur run --since origin/main --test spec/billing_spec.rb`.
A changed Ruby file whose changed lines cover no method mutates nothing; the run
warns and names the file instead of silently selecting zero subjects. An untracked
file inside the configured `include` set counts as fully changed: a brand-new,
never-committed source file is selected in full rather than silently skipped,
because a diff cannot see it (#295). The union reads race-free
(O_NOFOLLOW/O_NONBLOCK, validated on the opened descriptor) and streams its
line count, so a swapped-in symlink or FIFO is skipped quietly and a huge
untracked fixture outside `include` is never even opened. Comment-only
or formatting-only changes within discovered methods are skipped without this
warning; the run reports those skipped methods. A changed Ruby file that an
include pattern covers but `c.exclude` removes mutates nothing either, and the
run warns and names up to five such files - narrow or remove the `c.exclude`
entry, or pass the file as a positional source operand (configured excludes are
then ignored). `--subject` cannot help here: it filters subjects inside the
files left after excludes.

**Unreleased on main:** constant-literal diffing and `element_removal` are
not in v0.7.0.

A changed entry of a constant hash or array literal is a behavior change no
method owns, so `--since` also selects those assignments as subjects (#306).
`RULES = { city: "required", zip: "optional" }.freeze` gains a `state:` entry,
and `pair_removal` proposes removing each changed pair; the default-on
`element_removal` operator does the same for changed elements of array
literals (`%w[...]` included). A constant mutant runs against the specs that
cover a line reading the constant - and the specs can read the constant
directly - and the whole file is re-evaluated because re-assigning a constant
is not a method swap. The diff scope is line-granular: a literal written on a
single line puts every entry on that line in scope, so write one entry per
line to mutate only what changed. Unchanged entries on unchanged lines are
not mutated, and entries matching the arid patterns are skipped like arid
statements in a method.

Boundaries are named, never silently scored. A changed constant assignment
saboteur cannot mutate - a namespaced target, `||=`/`&&=`, a value that is
not a hash or array literal (only `.freeze` calls are looked through), a
write guarded by `if`/`unless`, or a constant written more than once in one
file (any later write wins, literal or not) - gets a diagnostic instead of
mutants. Two rules can skip a changed constant entirely, each with its own
warning. First, the replay rule: a constant mutant re-evaluates its whole
file, so whatever runs at load runs again on every mutant. saboteur replays
a file only when its load-time code is limited to forms it recognizes -
`require`/`require_relative`, pure defs, class/module nesting and plain
literal assignments - and trips no entry of the hazard denylist. Anything
else at load (a helper call, a registration, a write to disk, a class
factory) skips the file's constants with a warning; list the constant in
`c.whole_file` to replay the file anyway, or move the literal into its own
file. Passing the check is not a promise that replaying the file is safe -
it only means no unrecognized code runs at load. Second, observability:
when every read of the constant captures the value at load time in another
file (`COPY = A::RULES`, including a capture inside a boot-time block such
as `1.times { COPY = A::RULES }`), the original object is already held and
no test can observe a change, so the constant is dropped with a diagnostic
rather than reported Survived. The block rule is conservative: a block
passed to a deferring call runs later, but saboteur prefers dropping a
constant over an unobservable survivor. Consumer matching is a lexical
heuristic: reads reached through a superclass, `const_get`, or a compact
`class Shop::Item` scope are not resolved, and a constant only read that
way reports ran-at-load or no-coverage rather than a guessed survivor.

Without `--test`, the run infers the specs: the spec named after each mutated
file (`lib/a/b.rb` runs `spec/a/b_spec.rb`; `app/` files and `spec/lib/` work
too, and a dashed path also tries its underscored require name:
`lib/acts-as-taggable-on/x.rb` finds `spec/acts_as_taggable_on/x_spec.rb`) runs for the baseline passes, the coverage pass and every mutant, as
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

**Unreleased on main:** `--since` also runs every spec file the diff adds or
changes, subject to the suite rules below. v0.7.0 runs only the inferred specs.

With `--since`, every spec file under the root that the diff adds or changes
(committed since the base, uncommitted or untracked) also runs, next to the
inferred specs and listed once. A pull request often tests a change through a
request or controller spec whose name maps to no changed file; without it a
mutant only that spec kills would survive. A changed file runs only when the
configured suite loads it, by RSpec's own rules (`.rspec`, `rspec_args`, the
default path, `--pattern` and `--exclude-pattern`), and it is a regular file:
RSpec applies its patterns only to the directories it scans, so a fixture spec
the suite excludes must not run just because the diff touched it. Patterns
are read from options only: a `pattern` or `exclude_pattern` set in Ruby
(`RSpec.configure` in a spec helper) is not seen, so put exclusions in `.rspec`
or `rspec_args`. The spec inferred from a changed file's name runs as before,
whatever the patterns say. Unchanged
specs are not added, and changed support files such as `spec_helper.rb` are not
run as specs. A changed `*_spec.rb` that does not run is named with the reason:
deleted in the diff, left out by the suite's patterns, or a symlink or other
non-regular file; that note also comes before a stop on an unmatched file.
Changed specs join only a run that mutates something. An
unmatched file still stops the run; when the diff deleted its expected spec
(a rename, say), the message says so and lists the changed specs to pass to
`--test`. `--test` runs exactly the files you name, so a changed spec you do
not name does not run, and `--all` runs the whole suite as before.

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

### External test commands (unreleased on main)

`--test-command CMD` (config `c.test_command`, #140) replaces the whole
in-process test machinery: for each execution a fresh pristine copy of the
project tree is materialized under the system tmp dir, the mutant is
written into that copy - never your real files - and CMD runs there with
the copy as its working directory. Neutral runs (baseline probes and
verification re-runs) write the file's unchanged bytes, so a neutral copy
is byte-identical to the pristine tree. The exit status decides the
verdict: 0 survived, non-zero killed (except the shell's 126/127, which
read as command/setup errors), the per-mutant deadline
(`c.baseline_timeout`) a timeout. Use it when the target app cannot load
inside saboteur's Ruby, for example an app pinned to an older Ruby.

**Warning: CMD runs unsandboxed with your user permissions - full network
access and every side effect it chooses, exactly as if you typed it into a
shell.** Only point it at commands you trust. The per-execution copy is
the only tree CMD is pointed at, and mutants are applied there, so nothing
saboteur writes can reach the real tree - but the copy is not a jail, and
a command that goes looking for your real files can still touch them.
Symlinks are not followed into the real tree: a relative link that
resolves inside the project is rebuilt inside the copy as a relative
link, so requiring an alias sees the same - possibly mutated - content
as the real path. A link that escapes the tree or loops is refused with
an error naming the path, and so is an absolute link even when it points
into the project: it resolves to the real tree, not the copy. Captured
output is held in memory and capped at 64 KB.

On every shutdown path saboteur terminates the command's whole process
group, escalating from SIGTERM to SIGKILL, including on Ctrl-C. One case
is outside that guarantee: if saboteur itself is SIGKILLed it cannot send
those signals, so the group may keep running against the leftover copy,
and the temp directory may not be cleaned up. Descendants that escaped
the process group (setsid or daemonized) are outside that cleanup too:
the run does not wait for them, but they keep running until they exit.
Saboteur's own mutation writes still never touch the real tree - the
leftover state lives only under the system tmp dir.

The mode is explicitly slower: the whole command runs once per mutant, so
a mutant count in the hundreds means hundreds of full suite runs, plus one
recursive copy of the project per execution, mutant or neutral. It is
serial, uses no coverage and no test selection, skips the baseline and
the sandbox, applies no resource caps to the command, and cannot combine
with `--test` or `--incremental` (config `tests:`/`incremental:` count
too; `sandbox: "strict"` is rejected because it cannot be honored). Before
any mutant is created, one neutral preflight runs CMD on the unchanged
copy: a command that fails there fails the whole run up front with its
exit status and captured output (exit 3). The preflight runs under an absolute
deadline - whichever ends sooner, its own `c.baseline_timeout` slice or
the overall run budget. The deadline bounds when the command is admitted
and how long the run waits for it; the tree copy beforehand and the
TERM/KILL grace and capture drain afterward are not charged to it. A
budget already spent, or spent while waiting, is a budget stop, not a
command failure. A blank `--test-command` is a
config error. A saboteur run refuses to start inside CMD's own
environment, so a test command that itself invokes saboteur cannot mutate
the copy mid-run.
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

### Output, reports and scores

| Output | Default | Best for |
| --- | --- | --- |
| Terminal report | stdout; progress on stderr | Human triage and the full replay command. |
| JSON report | `.saboteur/report.json` | CI, dashboards, findings and stable machine evidence. |
| HTML report | `.saboteur/report.html` | Reviewing survivors in a self-contained browser page. |
| Agent JSON | stdout with `--agent` | Automation: exactly one bounded JSON payload. |
| Score history | off by default | Comparing covered score across matching selections. |

The terminal puts survivors first, then a short summary last, so the summary stays on
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
`--config` or the default config path. On main, an empty `--operators` or
`--exclude-operators` list is left out unless you typed it: the config the
command reads again supplies the same empty list, while a typed
`--exclude-operators ''` may clear a configured exclusion and so stays.
v0.7.0 keeps that empty list in the replay command.
Only knobs that cannot change a by-digest replay (`--max-mutants-per-method`,
`--fail-fast`, `--threshold`) are left out. The agent protocol instead omits a command
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
survivor's notes. **Unreleased on main:** each survivor in the JSON report also carries a
`classification` field: `likely_equivalent` (the mutant compiles to the
original's instructions), `arid` (every line an edit touches matches an
arid pattern), or `missing_test` (a planned covering test passed with the
mutant applied). One label per survivor, first match in that order; the
field is omitted when no signal applies. Labels are heuristics for triage
order, not diagnoses - inspect a survivor before acting on its label, and
never add a test or ignore a mutant from the label alone. Labels never
change scores or the exit code. When a classification signal applies, the
HTML report shows the label next to the survivor's status, and the agent
JSON carries it on the shown finding. See
[docs/guides/reading-survivors.md](docs/guides/reading-survivors.md). The
JSON report goes to `.saboteur/report.json` and a self-contained HTML
report (one file, no scripts, no network) to `.saboteur/report.html`. Change
the paths with `--json` / `--html` or `c.json_report` / `c.html_report` in
`config/saboteur.rb`; set either to `nil` to turn that report off. The two paths
must differ. When an artifact cannot be written - a read-only tree inside a
sandboxed run - the HTML report and the score history warn and the run still
exits by its results. An explicitly requested JSON report (`--json` or
`c.json_report`) is different: it is the completion evidence an outer harness
trusts, so a failed write fails the run with exit 3 rather than leaving a
stale or partial file presented as this run's; the default
`.saboteur/report.json` stays best-effort. The HTML page shows the covered mutation score
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
subject, operator, original and replacement that a pull-request note
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

| Exit code | Meaning |
| --- | --- |
| 0 | Complete pass: no unignored survivors, or the covered score meets `--threshold`. |
| 1 | Test signal: unignored survivors, the covered score is below `--threshold` or missing, or a configured error/timeout limit is exceeded. |
| 2 | Invalid use: bad configuration, a missing source or test, or an unsupported combination. |
| 3 | Tool failure or an incomplete run: internal error, error majority, or any errored/resource-limited mutant with `--threshold`. |
| 4 | Text-mode `--max-duration` budget exhausted; `--max-duration-ok` and agent mode keep verdict-driven exits. |

Unexpected `StandardError` or `LoadError` failures print
`saboteur: internal error (...) - please report it` and exit 3, rather
than dying with a bare stack trace and an accidental exit code. The full
backtrace lands in `<cache_dir>/internal-error.log` (default
`.saboteur/`), and `--verbose` also prints it to stderr. When the cache
dir cannot hold the log, a private pid-keyed fallback in the system temp
dir takes it (created with `O_EXCL | O_NOFOLLOW`, mode 0600, so it never
follows or overwrites a pre-existing path). Logs are always written
private, and a nested run reads them back only through a no-follow,
non-blocking descriptor - a regular file, same owner, no group/other
bits (or, where the platform lacks those flags, only the `O_EXCL` temp
fallback is written and no excerpt is read). The message names the log only
after a successful write: an unset `cache_dir`, or a log writable nowhere,
leaves the one-liner standing alone. The executable
loads the crash reporter before the CLI, so a failure while it is
loading, being built, or parsing arguments gets the same report;
failures earlier than that - coverage setup or the reporter's own load -
get only the bare one-liner and still exit 3. Once the crash
reporter has loaded, agent mode reports the same failure as agent
JSON, using a standalone payload if the agent reporter has not
loaded. Before the crash reporter loads, only the one-line
diagnostic and exit 3 are available.
`--max-duration 10m` budgets the whole run, baselines included: the budget is checked before every subject and between mutants inside one, so past the budget the run finishes only the mutant in flight (bounded by its timeout), then stops before the next subject. Admitted phases (baseline checks, the coverage map build) are capped at the time left, as are verdict checks and timeout calibrations - admission is per check and per sequence, so nothing forks with no time left. A phase that hits only its budget-shortened cap stops the run as budget-exhausted rather than failing as a suite error. A kill or timeout the budget leaves uncheckable is reported as `unverified` - outside the score, never cached, listed under the early stop - instead of becoming an error, reports which selected subjects never ran and which mutants were omitted, marks the JSON and agent output partial (`earlyStop.reason: "max_duration"`), and exits 4; `--max-duration-ok` (or `c.max_duration_ok = true`) leaves the exit to the plain verdict instead, which can still fail the run - 1 on survivors, 3 when the budget stopped the run before any mutant verdict was verified. In agent mode the exit code stays verdict-driven and the budget shows up in `incomplete[]` and `earlyStop` (#245).

### Rejected kills

The terminal lists them in a `Rejected kills` section and annotates the error
count (`error 3 (2 rejected kills)`); JSON flags each rejected mutant with
`rejectedKill: true` and keeps the `rejectedKills` count. These are fresh
per-mutant kill claims whose tests also fail with the method unchanged. They
stay errors outside the score. Timeout checks, other errors and reused cached
kills are not included. See [rejected kills](docs/rejected-kills.md) for
details.

<a id="configuration"></a>
## ⚙️ Configuration

`config/saboteur.rb` in the project root; CLI flags override it. Keep the shared
config usable for whole-project runs and pass `--since` in the pull-request
job. A PR-only config may set `c.since = "origin/main"`; omit `since` (or use
`c.since = nil`) in the config for audits on main. Use your actual target branch.

### Common settings

| Setting | Default | Use |
| --- | --- | --- |
| `c.include` | `["lib/**/*.rb"]` | Source files to mutate. |
| `c.exclude` | `[]` | Remove sources from `include`. |
| `c.require` | `[]` | Boot files loaded before tests. |
| `c.jobs` | `1` | Mutation worker processes. |
| `c.threshold` | none | Minimum covered score for CI. |
| `c.max_duration` | none | Whole-run wall-clock budget in seconds. |
| `c.max_mutants_per_method` | `100` | Cap valid mutants per covered method. |
| `c.incremental` | `false` | Reuse verdicts whose recorded inputs are unchanged. |
| `c.sandbox` | `true` | Read-only project tree for mutant children where supported. |
| `c.ignore_file` | `config/saboteur_ignore.rb` | Accepted survivors; triage state is unreleased on main. |
| `c.score_history` | off | Append one score-history JSONL record per finished report. |

### Reference example
- saboteur is RSpec-only and needs `fork`: no Windows, no Minitest.
- A survivor is review evidence, not proof of a bug in your tests. It can
  be a missing test, an equivalent change, a flaky test, or a limit of
  the tool. Read it before you write a test for it.
- `--since` and `--incremental` are iteration aids. Run the whole project
  on main and before a release.
- The hazard guard is syntactic, sandboxing varies by platform (Landlock
  on Linux 6.2+; mutants run unsandboxed on macOS), and network access is
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

## License

[MIT](LICENSE).
