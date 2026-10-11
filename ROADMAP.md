# Roadmap

This file says where saboteur is going and in what order. It is a plan, not a
promise. Dates are left out on purpose: each milestone ships when its exit
criteria are met.

## Goal

Make saboteur the mutation testing tool a Ruby team can run on every pull
request without thinking about it. Three things decide that:

1. **Speed.** A run must be fast enough to sit in CI.
2. **Trust.** A survivor must mean something, and a kill must be real.
3. **Reach.** It must be easy to find, install and wire into CI.

## Where we are (0.2.0)

Already shipped:

- Per-mutant test selection by line coverage, likeliest killers first.
- Coarse-first mutation (`nil` / `raise` per method before fine mutants).
- Diff mode (`--since origin/main`) and `--incremental` verdict reuse.
- Supervised child processes with deadline, memory and process caps.
- Stryker-schema JSON report and a pluggable mutation source API.
- RSpec only, by design. Validated on four gems and two Rails 8.1 apps.

Performance work on memory use around `fork` is in flight as a separate pull
request.

Known gaps, taken from our own benchmark against
[mutineer](https://github.com/davidteren/mutineer) (MIT): fewer operators, no
baseline file, no HTML report, no ready-made GitHub Action.

## Design rules

These apply to every milestone. A change that breaks one of them needs a
written reason in its pull request.

- **Test first.** Write the failing spec, then the code. A bug fix starts
  with a spec that reproduces the bug.
- **One reason to change.** Each class does one job: find subjects, generate
  mutants, select tests, run, report. New behaviour goes in a new class, not
  in a bigger one.
- **Extend, do not edit.** New operators, reporters and test frameworks plug
  in through the public interfaces (`MutationSource::Base`,
  `Integration::Base`, hooks). The core does not learn about them.
- **Depend on small interfaces.** Collaborators are passed in, so tests can
  replace them. No hidden globals.
- **Deterministic.** Same code, same seed, same verdicts. A flaky result is a
  bug in saboteur.
- **Simple English.** Error messages, docs and report text say what happened
  and what to do next.
- **Public API is a contract.** Anything listed under "Extending" in the
  README stays stable across minor versions.

## Milestone 1: Fast enough for CI (0.3)

Speed is the first reason teams give up on mutation testing.

- Land the fork memory work and publish before/after numbers on a Rails app.
- Make `--since` the documented default for pull requests, and measure it on
  a real branch history.
- Stop spending time on dead ends: skip subjects with no coverage and cap
  mutants per method with a configurable limit.
- Keep a stable benchmark harness in `bench/` so every release can show its
  speed and memory next to the last one.

Exit criteria: a typical pull request run on a mid-size Rails app finishes in
a few minutes, and the numbers are in the repo.

## Milestone 2: Trust the result (0.4)

A score is only useful if people believe it.

- **Equivalent mutants.** Detect the common safe cases (for example a changed
  literal that a method never reads) and mark them. Everything else keeps
  the explicit ignore list with a required reason.
- **Real kills only.** Keep the fake-kill check (a test that fails for any
  change, such as a boot error) and report how many kills it rejected.
- **Flaky-test guard.** Re-run the baseline suite with the run seed and
  refuse to start if it is not green and stable.
- **Stable digests.** A mutant keeps the same digest across runs, so ignore
  entries do not rot.
- **Self-hosting.** Run saboteur on its own code in CI and publish the score.
  Start with an honest threshold and raise it over time.

Exit criteria: two runs of the same code and seed give identical verdicts, and
saboteur's own score is visible on every pull request.

## Milestone 3: Fits into a team's workflow (0.5)

- **GitHub Action.** One step that runs diff mode on a pull request, posts the
  score and the survivors as a comment, and sets the check status.
- **Baseline file.** Accept today's survivors, fail only on new ones. This is
  how an existing project adopts mutation testing without a cleanup week.
- **Reports.** A self-contained HTML report next to the JSON one, and
  plain-text output that reads well in CI logs.
- **Config check.** `saboteur doctor` prints what it found: Ruby version,
  coverage setup, SimpleCov conflicts, boot files. It names the fix.
- **More operators**, added one by one through the mutation source API, each
  with a spec that shows a mutant it kills and a mutant it should not
  produce.

Exit criteria: a new project can add the Action and get a useful pull request
comment in under ten minutes.

## Milestone 4: Wider coverage of Ruby projects (0.6)

- Verify and document MySQL and older Rails versions.
- Linux and macOS in CI for saboteur itself, on every supported Ruby.
- Better handling of metaprogramming-heavy code (`define_method`,
  `class_eval`), with documented limits where it cannot work.

Exit criteria: a compatibility table in the docs, backed by runs, not guesses.

## Milestone 5: 1.0

- Freeze the public API and the report schema. Publish a deprecation policy.
- Full documentation: a getting-started page, a "reading a survivor" guide,
  and a guide to writing a mutation source.
- A security note on running untrusted code in child processes.
- At least a handful of public projects using saboteur in CI.

Exit criteria: no known correctness bugs, and an API we are willing to keep.

## Outreach

Work that runs alongside the milestones:

- Keep the site and the benchmark page current with every release.
- Write up the benchmark honestly, including where mutineer wins.
- Post to Ruby Weekly and the Ruby community, and submit a talk to a Ruby
  conference such as RubyConf India once Milestone 2 is done.
- Open issues labelled "good first issue" for operators and reporters, since
  the plugin API makes them small and safe to review.

## Not planned

- Support for test frameworks other than RSpec. saboteur is deliberately
  RSpec-only. Doing one framework well beats doing two halfway. The
  `Integration::Base` interface stays public for anyone who wants to build
  their own.
- Anything that needs a hosted service to run. saboteur stays a local tool.

## How this file changes

Open a pull request. Milestones are reordered only with a reason that appears
in the description. When a milestone ships, move it to the changelog.
