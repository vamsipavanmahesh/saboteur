# Frequently asked questions

Short answers, each with a link to the full story.

## Does saboteur support Minitest?

No. saboteur is RSpec-only by design, and there is no supported way to point
it at another test command today. [Minitest](minitest.md) records how much of
the engine is RSpec-specific and what an adapter would take.

## What do I need to run it?

Ruby 3.3 or newer on Linux or macOS, and an RSpec suite. Rails works; the
defaults target plain gems, so a Rails app sets `c.include`, `c.require` and
`c.rails = true` (see the Quickstart on the [project site](index.html)).

## Which databases does it support?

PostgreSQL and SQLite, including parallel workers (`--jobs N`), where each
extra worker gets its own database copy. MySQL is not supported for `--jobs`
above 1, and older Rails versions have not been tried yet - the tested matrix
is in the README under [Benchmarks and validation](../README.md#benchmarks-and-validation).

## The baseline fails with "Could not find table" on a sqlite in-memory database

A sqlite `:memory:` database is per-process: saboteur's forked children
reconnect to a fresh, EMPTY in-memory database, so a schema loaded at
require time is gone. The refusal names the remedies: load the schema in a
`before(:suite)` hook, or in an `after_fork` hook
(`config/saboteur_hooks.rb` via `c.hooks`). Rails apps with file-backed
sqlite, PostgreSQL or SQLite test databases are unaffected.

## Does saboteur work with SimpleCov?

Not at the same time. saboteur needs Ruby's `Coverage` library for itself, so
SimpleCov must be off for the run. Most projects already guard SimpleCov with
an environment variable; key it so saboteur runs skip it.

## How do I turn colour on or off?

Every command that prints text takes `--color=always`, `--color=never` or
`--color=auto` (the default; `NO_COLOR` and a non-terminal output also turn
it off). `--no-color` is a deprecated alias for `--color=never`. A command
with nothing to colour accepts the flag and ignores it.

## What do the exit codes mean?

| Exit | Meaning |
| --- | --- |
| 0 | Clean: no unignored survivors (or `--threshold` met) |
| 1 | Survivors to review, or the score is below `--threshold` |
| 2 | Usage or configuration error, including a mutated file with no conventional spec |
| 3 | Tool failure or an incomplete run, such as most mutants erroring, or a `--since` run that skipped every subject of the change (refinements, no coverage), so the change is unverified |
| 4 | The `--max-duration` budget stopped the run (never with `--max-duration-ok`) |

Agent mode (`--agent`) has no exit 4 and reports budget exhaustion as partial
evidence instead. The full contract, including how these change between
releases, is the [stability policy](stability.md).

## Why did a kill turn into an error?

Every kill is re-run against the unchanged code. If the same tests fail there
too, the kill is rejected and stays outside the score - the test was failing
for its own reasons, not because of the mutant. The JSON report counts these
as `rejectedKills`; see [Rejected kills](rejected-kills.md).

## A survivor looks impossible to kill. Now what?

It may be equivalent: a change no test could ever notice, such as swapping
`min` for `max` where the inputs are always equal. Read the diff, decide, and
if it is equivalent or accepted risk, record it in `config/saboteur_ignore.rb`
with a reason - entries without a reason are rejected. The ignore list changes
the exit code, not the score. [How to read survivors](guides/reading-survivors.md)
walks one survivor from output to killing test, and [Survivor ranking](survivor-ranking.md)
explains the review order.

## Why is the first run slow?

Before any mutant runs, saboteur runs the unchanged tests twice (a cached
coverage map does not skip this) and builds a per-test coverage map. Later
runs reuse the map and verdicts (`--incremental`). To go faster: scope with
`--since origin/main` or `--test`, drop to one baseline pass with
`--baseline-passes 1`, cap the wall clock with `--max-duration 10m`, or run
the `saboteur pr` preset, which bundles all three.

## What does the score count?

The headline score is `(killed + timeout) / (killed + survived + timeout)`:
only mutants that ran. Errors, resource-limit stops and no-coverage work sit
outside it. A high score does not prove broad coverage or the absence of
flaky tests. [Scores](scores.md) defines every number on the report.

## Where do the reports go?

The JSON report is `.saboteur/report.json` in the Stryker
mutation-testing-report format, so existing viewers can open it. Pass
`--html PATH` for an HTML report. `.saboteur/` also holds the coverage and
verdict caches; those internals are not a stable API.

## Can it run in CI?

Yes: saboteur ships a GitHub Action that runs diff mode on pull requests and
is advisory by default. See the [GitHub Action guide](github-action.md).

## What is the warning about threads at fork time?

Threads do not survive `fork`, so a run names any thread alive when workers
fork. Two are well known: the ActiveRecord pool reaper, expected harmless
because saboteur's rails mode reconnects children to the database, and the
debug gem's remote console, which can pause children depending on
`RUBY_DEBUG_FORK_MODE` - for unattended runs, do not start the remote
debugger at all. Any other thread gets a generic caveat: background work a
mutant's test relies on may not run in the child, so results can differ.

## What is the warning about uncommitted changes?

Mutants run your code and could alter or delete files, so before a run on a
tree with uncommitted changes saboteur warns and splits the count by what is
at stake (#309, #316). Each change lands in one group, so the groups add up to
the count: saboteur setup files (the config file the run reads, plus the
Gemfile `BUNDLE_GEMFILE` names and its lock when that is not the root's own
`Gemfile`), the mutation scope (a Ruby file the configured `include` and
`exclude` select, or a path they match, such as a deleted source), and everything else, each
split into tracked and untracked. Up to five paths are named for the scope and
for the setup files. A change is counted the way `git status` lists it: a
rename once under its new path, a deletion under the deleted path (a deleted
source still counts as in scope), and every file of an untracked directory on
its own. saboteur's cache and reports never count. The scope is the configured
one: `--since`, `--subject` and source operands narrow a run further after the
warning.

```
saboteur: warning: 3972 uncommitted or untracked change(s) in the working tree: none inside the mutation scope, 3969 outside it (0 tracked, 3969 untracked), 3 saboteur setup file(s) (0 tracked, 3 untracked).
  setup files: config/saboteur.rb, Gemfile.saboteur, Gemfile.saboteur.lock
  Mutants run your code and could alter or delete files; run on a clean, committed tree or a CI checkout.
```
