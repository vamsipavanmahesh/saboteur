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
- **Limit incidental coverage.** A test that reaches a method only through a
  deep call chain says little about that method. Let a project count a test
  as covering a method only when the call depth from the test is under a
  limit, and report how many tests this removed. A lower limit is faster and
  leaves more survivors, so the default stays off until we measure it. The
  idea comes from
  [mutmut's stack depth limit](https://github.com/boxed/mutmut).
- **Line-level diff scope.** `--since` picks whole methods today. Add an
  option to mutate only the lines a branch touched, as Infection does with
  [`--git-diff-lines`](https://infection.github.io/guide/command-line-options.html)
  and Google does for every change
  ([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)). Measure the
  saving against the method-level default before choosing which one the
  pull-request guide recommends.
- **Research spike: mutant switching.** Define all mutants of a file once and
  pick the active one by id at run time, instead of rewriting and reloading
  per mutant. This is the idea behind
  [mutant schemata](https://www.albany.edu/faculty/offutt/research/papers/schema.pdf)
  (Untch, Offutt and Harrold), which reports a large speedup over
  interpretive mutation systems. Ruby has no compile step to save, so the
  gain is unknown. The spike ends with a measured yes or no, and it follows
  the proof rules in AGENTS.md.
- Keep a stable benchmark harness in `bench/` so every release can show its
  speed and memory next to the last one.

Exit criteria: a typical pull request run on a mid-size Rails app finishes in
a few minutes, and the numbers are in the repo.

## Milestone 2: Trust the result (0.4)

A score is only useful if people believe it. Google found that 85% of the
mutants it first showed developers were unproductive, and fixed that by
suppressing whole classes of them, which raised the productive share to 89%
([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)). Trust work comes
before more operators.

- **Equivalent mutants, cheap checks first.** Detect the common safe cases
  (for example a changed literal that a method never reads) and mark them.
  Add a Ruby version of
  [trivial compiler equivalence](http://www0.cs.ucl.ac.uk/staff/Yue.Jia/resources/papers/PapadakisJHT2015.pdf):
  if the mutated method compiles to the same instruction sequence as the
  original, the mutant is equivalent and is not run. That paper found about
  30% of equivalent mutants this way. Everything else keeps the explicit
  ignore list with a required reason.
- **Arid code, by rule and by project.** The built-in list already skips
  logging and metrics calls. Make the list extensible in `.saboteur.yml`,
  with a required reason per entry, and print how many mutants each rule
  removed. Google's largest gains came from three rules: logging, time and
  deadlines, and configuration flags. Check those last two against Ruby
  code.
- **Inline ignore comments.** A `# saboteur:disable <operator> <reason>`
  comment for a one-off equivalent mutant, next to the code it excuses, like
  [Stryker's disable comments](https://stryker-mutator.io/docs/stryker-js/disable-mutants/).
  Ignored mutants stay in the report with the status "ignored" and do not
  count against the score.
- **Real kills only.** Keep the fake-kill check (a test that fails for any
  change, such as a boot error) and report how many kills it rejected.
- **Defined statuses and score.** Document each status and the formula for
  the score. Follow the
  [Stryker definitions](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/)
  so reports from both tools read the same: timeouts count as detected,
  runtime and compile errors are invalid and stay out of the score, and a
  second score is shown for covered code only.
- **Flaky-test guard.** Re-run the baseline suite with the run seed and
  refuse to start if it is not green and stable.
- **Stable digests.** A mutant keeps the same digest across runs, and an
  edit elsewhere in the file does not change it. go-mutesting's
  [blacklist](https://github.com/zimmski/go-mutesting) documents the
  failure we want to avoid: a change in the source changes every checksum.
  The spec for this is an edit above a mutant that leaves its digest alone.
- **Redundant mutants.** Measure how often two mutants of one method are
  killed by exactly the same tests in our validation runs. If the overlap is
  high, drop the operator replacements that
  [subsumption research](https://www.albany.edu/faculty/offutt/research/papers/MiniMutant-ICST2014.pdf)
  predicts are redundant. The comparison table already follows this idea
  (see Kaminski, Ammann and Offutt in `mutation_source/builtin.rb`).
  Any removal needs the verdict parity check from AGENTS.md.
- **Self-hosting.** Run saboteur on its own code in CI and publish the score.
  Start with an honest threshold and raise it over time.

Exit criteria: two runs of the same code and seed give identical verdicts,
saboteur's own score is visible on every pull request, and the report shows
how many mutants each suppression rule and each equivalence check removed.

## Milestone 3: Fits into a team's workflow (0.5)

- **GitHub Action.** One step that runs diff mode on a pull request, posts the
  score and the survivors as a comment, and sets the check status.
- **Few, useful survivors in the comment.** Show a capped number of
  survivors per pull request, ordered by the likeliest to matter, with the
  rest in the report. Google surfaces at most one mutant per changed line
  because findings that are not actionable annoy reviewers
  ([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)). Add a
  "not useful" label to the survivor diff so a team can turn a repeated
  complaint into an arid rule.
- **Baseline file.** Accept today's survivors, fail only on new ones. This is
  how an existing project adopts mutation testing without a cleanup week.
- **Thresholds.** `--min-score` and `--min-covered-score`, the two gates
  Infection offers as
  [`--min-msi` and `--min-covered-msi`](https://infection.github.io/guide/command-line-options.html),
  and a limit on timeouts so a loop-heavy change cannot pass by timing out.
- **Reports.** A self-contained HTML report next to the JSON one, built on
  the report schema we already write, and plain-text output that reads well
  in CI logs.
- **Replay one mutant.** `saboteur run --mutant <digest>` re-runs a single
  mutant and prints its diff and the tests it ran, as Infection does with
  [`--id`](https://infection.github.io/guide/command-line-options.html) and
  mutmut does from its [browse screen](https://github.com/boxed/mutmut).
  Fixing a survivor should not need a full run.
- **Config check.** `saboteur doctor` prints what it found: Ruby version,
  coverage setup, SimpleCov conflicts, boot files. It names the fix.
- **More operators**, added one by one through the mutation source API. Each
  needs a spec that shows a mutant it kills and a mutant it should not
  produce, and a written reason: the operator catches a kind of real fault
  that the current set misses. Just et al. found that about 10% of real
  faults need a new or stronger operator and 17% are not coupled to any
  mutant ([FSE 2014](https://homes.cs.washington.edu/~mernst/pubs/mutation-effectiveness-fse2014.pdf)),
  so the best source of operators is the bug-fix history of Ruby gems, not a
  list from another language. Candidates to evaluate first are
  swaps inside common Ruby method families (for example `select`/`reject`
  and `first`/`last`); each must pass the same test before it ships.

Exit criteria: a new project can add the Action and get a useful pull request
comment in under ten minutes, and every operator added in this milestone has
a documented real-fault reason.

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
- Language-model generation of mutants or language-model equivalence checks
  in the core. Meta reports that its equivalence judge alone had 0.79
  precision and 0.47 recall, and only reached 0.95 and 0.96 with extra
  pre-processing
  ([Foster et al., 2025](https://arxiv.org/html/2501.12862)). Deterministic
  checks come first. A plugin on the mutation source API may try it.

## Where these ideas come from

Reference list for the items above. We take ideas from papers and open source
tools, never code from them, and never from the commercial mutant gem (see
AGENTS.md).

- Just et al., [Are mutants a valid substitute for real faults?](https://homes.cs.washington.edu/~rjust/publ/JustJIEHF2014b-abstract.html)
- Petrovic and Ivankovic, [State of mutation testing at Google](https://research.google/pubs/state-of-mutation-testing-at-google/)
  and [Practical mutation testing at scale](https://arxiv.org/pdf/2102.11378)
- Foster et al., [Mutation-guided LLM-based test generation at Meta](https://arxiv.org/html/2501.12862)
- Offutt et al., [An experimental determination of sufficient mutation operators](https://people.cs.gmu.edu/~tr-admin/papers/ISSE-TR-94-00.pdf)
- Ammann, Delamaro and Offutt, [Establishing theoretical minimal sets of mutants](https://www.albany.edu/faculty/offutt/research/papers/MiniMutant-ICST2014.pdf)
- Papadakis et al., [Trivial compiler equivalence](http://www0.cs.ucl.ac.uk/staff/Yue.Jia/resources/papers/PapadakisJHT2015.pdf)
- Untch, Offutt and Harrold, [Mutation analysis using mutant schemata](https://www.albany.edu/faculty/offutt/research/papers/schema.pdf)
- Tools: [PIT incremental analysis](https://pitest.org/quickstart/incremental_analysis/),
  [StrykerJS incremental mode](https://stryker-mutator.io/docs/stryker-js/incremental/),
  [Infection](https://infection.github.io/guide/command-line-options.html),
  [mutmut](https://github.com/boxed/mutmut),
  [go-mutesting](https://github.com/zimmski/go-mutesting),
  [mutineer](https://github.com/davidteren/mutineer) (MIT)

## How this file changes

Open a pull request. Milestones are reordered only with a reason that appears
in the description. When a milestone ships, move it to the changelog.
