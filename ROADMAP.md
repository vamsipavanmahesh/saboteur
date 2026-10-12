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

## Where we are (0.3.0)

Already shipped:

- Per-mutant test selection by line coverage, likeliest killers first.
- Coarse-first mutation (`nil` / `raise` per method before fine mutants).
- Diff mode (`--since origin/main`) and `--incremental` verdict reuse.
- Supervised child processes with deadline, memory and process caps.
- Stryker-schema JSON report and a pluggable mutation source API.
- RSpec only, by design. Validated on four gems and two Rails 8.1 apps.

Known gaps, taken from our own benchmark against
[mutineer](https://github.com/davidteren/mutineer) (MIT): fewer operators, no
baseline file. A self-contained HTML report and a ready-made GitHub Action
now exist, but the Action is advisory and does not post a pull request
comment yet.

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

## How to read milestones 1 to 4

Each item says which of two things it is. **Shipped** means the code is in
`main` today and the item is about keeping it honest or making it stronger.
**Planned** means new work. Items marked **research** are spikes: they end
with a measured yes or no, they follow the proof rules in AGENTS.md, and they
are not part of a milestone's exit gate. Numbers quoted from papers describe
the study they came from, not Ruby and not saboteur.

## Milestone 1: Fast enough for CI (0.3)

Speed is the first reason teams give up on mutation testing.

- **Shipped:** the fork memory work (#4) and the pull-request guide with the
  `bench/since` harness (#5). **Planned:** publish before/after numbers on a
  Rails app.
- **Shipped:** `--since` restricts fine mutants to the changed lines and keeps
  the coarse mutants of each changed method (`Engine::DiffScope`).
  **Planned:** extend the existing selected-file measurement in
  `bench/since` to branch histories of the validation projects, and evaluate an optional
  method-wide scope next to it. A change in one line can break a test that
  only exercises the rest of the method, so the wider scope may find
  survivors the line scope misses. Ship it only if the measurement shows a
  cost worth paying. Infection offers both line and file filters
  ([`--git-diff-lines`](https://infection.github.io/guide/command-line-options.html));
  Google mutates only changed lines
  ([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)).
- **Shipped (#6):** skip subjects with no coverage and cap mutants per
  method. **Planned:** keep the score caveats from that change in the docs
  until the score work in Milestone 2 lands.
- **Planned, opt-in:** limit incidental coverage. A test that reaches a
  method only through a long call chain may be incidental to it, and running
  it for every mutant costs time. mutmut lets a project count a test only
  below a call depth
  ([mutmut](https://github.com/boxed/mutmut)), and its docs warn that a lower
  limit leaves more survivors that a deeper test would have caught. So the
  default stays off. Accept it only with a measured drop in tests run per
  mutant and a written list of the killers it lost on our validation
  projects.
- **Research: mutant switching.** Define all mutants of a file once and pick
  the active one by id at run time, instead of rewriting and reloading per
  mutant. This is the idea behind
  [mutant schemata](https://www.albany.edu/faculty/offutt/research/papers/schema.pdf)
  (Untch, Offutt and Harrold), which reports a large speedup for the
  interpretive systems of its time. Ruby has no compile step to save, so the
  gain is unknown.
- **Shipped:** `bench/` holds the benchmark harnesses. **Planned:** every
  release shows its speed and memory next to the last one.

Exit criteria: a typical pull request run on a mid-size Rails app finishes in
a few minutes, and the numbers are in the repo. Research items do not block
this milestone.

## Milestone 2: Trust the result (0.4)

A score is only useful if people believe it. In Google's study, developers
first classified 85% of the mutants shown to them as unproductive, and
suppression rules built from their feedback raised the productive share from
15% to 89% in that system
([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)). The lesson we
take is the method, not the numbers: collect feedback, then suppress by rule.

- **Shipped:** a configurable `arid` pattern list in `.saboteur.yml` (logging,
  metrics and instrumentation calls by default). **Planned:** a required
  reason per project entry, a count of mutants each rule removed, and a
  report line for each rule. A rule count says how much was suppressed, not
  that tests improved, and the report must not present it as a quality
  measure. Google's biggest gains came from logging, time and deadline, and
  configuration rules, so check the last two against Ruby code.
- **Shipped:** an ignore list with a required reason, and survivors shown as
  "ignored" but still counted. **Planned:** an inline
  `# saboteur:disable <operator> <reason>` comment next to the code it
  excuses, like
  [Stryker's disable comments](https://stryker-mutator.io/docs/stryker-js/disable-mutants/).
  Same status and same reporting as the ignore list.
- **Shipped:** the fake-kill check, with a per-cause kill count in the
  report. **Planned:** report how many kills it rejected.
- **Shipped:** self-hosting. CI runs saboteur on its own changed methods and
  fails on survivors that are not in `.saboteur-ignore.yml`. **Planned:**
  publish the score history and raise the bar over time.
- **Shipped:** mutant digests use offsets relative to the subject, so an
  edit above a method does not change them, and a spec covers it.
  **Planned:** keep it that way as operators are added, and add a spec per
  new operator. The failure to avoid is documented in
  [go-mutesting](https://github.com/zimmski/go-mutesting): a change in the
  source changes every checksum in its blacklist.
- **Planned: a defined score and a migration.** Today the score is
  (killed + timeout) / (killed + survived + timeout), so it is computed over
  covered mutants only, and accepted survivors still count. Stryker's main
  score also counts mutants no test covers, and shows the covered-only score
  second
  ([Stryker](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/)).
  Before changing anything, document the current meaning and label it
  "covered score". Then decide, in a pull request with consumer notes and
  specs, whether to add a second score and whether ignored mutants leave the
  score as Stryker does. Subjects skipped as uncovered by #6 do not generate
  mutants, so no exact "mutants without coverage" count exists for them. The
  report must say so instead of inventing a denominator. JSON consumers get
  additive fields first, and a field changes meaning only across a major
  version.
- **Planned: safer incremental reuse.** `ResultCache` states its known hole:
  a change in a method that the mutated method calls is not seen. Before
  `--incremental` is recommended for a required check, invalidate verdicts
  conservatively when relevant inputs change: a called method or helper, the
  config, the lockfile, the saboteur version. Each rule needs a regression
  spec. PIT documents the same class of risk for its history file
  ([PIT](https://pitest.org/quickstart/incremental_analysis/)), and
  [StrykerJS](https://stryker-mutator.io/docs/stryker-js/incremental/)
  shows its limits by how well the test runner reports test locations.
- **Planned:** a flaky-test guard. Re-run the baseline suite with the run
  seed and refuse to start if it is not green and stable. The report says
  whether a run completed clean, so a CI gate can tell "no useful work" from
  "nothing to find".
- **Research: equivalent mutants by instruction sequence.** Trivial compiler
  equivalence found that comparing compiled code detects some equivalent
  mutants
  ([Papadakis et al., 2015](http://www0.cs.ucl.ac.uk/staff/Yue.Jia/resources/papers/PapadakisJHT2015.pdf)).
  That study was on compiled C programs, and its roughly 30% is its sample,
  not a forecast for Ruby. The spike must first define what "identical"
  means for CRuby: literal pools, exception tables, source location metadata,
  and code that reads its own source or instructions. It pins the Ruby
  versions and compile options it tests. One rule is fixed now: a mutant is
  skipped only when equivalence is proven, and any doubt means the mutant
  runs. The spike ends with the measured hit rate and a count of wrong skips
  against a run with no skipping. Separately, conservative safe-pattern checks (for
  example a changed literal the method never reads) can be evaluated as
  proven pattern checks of their own.
- **Research: redundant mutants.** A fail-fast run records only the first
  killing test, so two mutants with the same first killer are not proven
  redundant. The experiment needs its own harness: a sampled run with
  fail-fast off that records every relevant test's result per mutant (a kill
  matrix). It defines which direction counts as subsumption, and it never
  groups mutants that no test kills, because survivors and equivalent
  mutants have an empty killer set and share nothing. An operator
  replacement is removed only if it is redundant in the matrix and does not
  lose real-fault detection on the validation projects. Checking verdicts on
  the mutants that remain cannot show that the removed ones were harmless.
  Background:
  [Ammann, Delamaro and Offutt, 2014](https://www.albany.edu/faculty/offutt/research/papers/MiniMutant-ICST2014.pdf).

Exit criteria: two runs of the same code and seed give identical verdicts,
saboteur's own score is visible on every pull request, the score has a
written definition with a migration note, and `--incremental` has the
invalidation rules and specs above.

## Milestone 3: Fits into a team's workflow (0.5)

- **GitHub Action.** One step that runs diff mode on a pull request and
  sets the check status. **Shipped:** a composite action
  ([docs/github-action.md](docs/github-action.md)) that is advisory by
  default, writes the covered score and survivors to the job summary and as
  workflow warnings, and fails on survivors when asked. It uses a read-only
  token, so it works on fork pull requests. **Planned:** posting the score and
  survivors as a pull request comment. That needs a token with write access,
  which fork pull requests never get, so it needs its own design: a separate
  trusted workflow that reads the report and never runs the pull request's
  code.
- **Survivors in the comment.** **Shipped:** in review mode the terminal
  output shows one survivor per line and counts the rest. **Planned:** a cap
  on survivors per pull request, with the rest in the report. The order
  needs a measurable rule before it ships, for example coarse before fine,
  then by whether a covering test exists, and we publish the rule. Google
  shows at most one mutant per changed line because findings that are not
  actionable annoy reviewers
  ([Petrovic et al., 2021](https://arxiv.org/pdf/2102.11378)). Add a "not
  useful" label to the survivor diff so a team can turn a repeated complaint
  into an arid rule.
- **Baseline file.** Accept today's survivors, fail only on new ones. This is
  how an existing project adopts mutation testing without a cleanup week.
- **Thresholds.** `--min-score`, `--min-covered-score` and a limit on
  timeouts, so a loop-heavy change cannot pass by timing out. Infection
  offers
  [`--min-msi`, `--min-covered-msi` and `--max-timeouts`](https://infection.github.io/guide/command-line-options.html).
  The names follow the score definition from Milestone 2.
- **Reports.** A self-contained HTML report next to the JSON one, built on
  the report schema we already write, and plain-text output that reads well
  in CI logs. The report metadata says how many mutants were selected,
  omitted by the per-method cap, skipped, and ignored, so a reader can see
  what the score covers.
- **Replay one mutant.** `saboteur run --mutant <digest>` re-runs a single
  mutant and prints its diff and the tests it ran, as Infection does with
  [`--id`](https://infection.github.io/guide/command-line-options.html) and
  mutmut does from its [browse screen](https://github.com/boxed/mutmut).
  Fixing a survivor should not need a full run.
- **Config check.** `saboteur doctor` prints what it found: Ruby version,
  coverage setup, SimpleCov conflicts, boot files, and whether the baseline
  suite is green. It names the fix.
- **More operators**, added one by one through the mutation source API. Each
  needs a spec that shows a mutant it kills and a mutant it should not
  produce, and a written reason: it catches a kind of real fault the current
  set misses. In their study, Just et al. found that about 10% of real
  faults needed a new or stronger operator and about 17% were not coupled to
  any mutant
  ([FSE 2014](https://homes.cs.washington.edu/~mernst/pubs/mutation-effectiveness-fse2014.pdf)).
  We take the method: look at bug fixes in Ruby gems before choosing
  operators, instead of copying a list from another language. Candidates to
  evaluate first are swaps inside common Ruby method families (for example
  `select`/`reject` and `first`/`last`); each must pass the same test before
  it ships.

Exit criteria: a new project can add the Action and get a useful pull request
result (a job summary now, a comment once that ships) in under ten minutes, and every operator added in this milestone has
a documented real-fault reason.

## Milestone 4: An Action a team can adopt (0.6)

Planned. This comes from a review of the mutineer GitHub Action by four
reviewers and was approved by the maintainer. The order below is the order of
work.

1. **Survivor annotations.** Per-survivor notes on the changed lines of the
   pull request diff, and a top-N survivor list in the job summary. This is
   the feature that shows the tool working inside a review.
2. **Exact base anchoring for diff scope.** Pin the pull request's
   `base.sha`, fetch a bounded amount of history, and fail closed when there
   is no merge base. The Action never falls back to a silent full scan.
3. **A "no new survivors" gate.** The adoption path for an existing project:
   stable mutant identity, baseline metadata (generator, config, scope),
   explicit acceptance of survivors, and a rule that an incomplete run is
   never reported as clean.
4. **A usable Action.** A `working-directory` input and an install test on an
   external repository, then a Marketplace listing with a `v1` tag and a
   badge.
5. **Threshold flags.** A covered-score floor and limits on timeouts and
   errors, added after the score semantics are documented. Scores are never
   compared across tools.

Exit criteria: a project that is not saboteur's own adds the Action, sees
survivor notes on its pull request, and can adopt the baseline gate without
a cleanup week.

## Milestone 5: Wider coverage of Ruby projects (0.7)

- Verify and document MySQL and older Rails versions.
- Linux and macOS in CI for saboteur itself, on every supported Ruby.
- Better handling of metaprogramming-heavy code (`define_method`,
  `class_eval`), with documented limits where it cannot work.

Exit criteria: a compatibility table in the docs, backed by runs, not guesses.

## Milestone 6: 1.0

- Freeze the public API and the report schema. Publish a deprecation policy.
- Full documentation: a getting-started page, a "reading a survivor" guide,
  and a guide to writing a mutation source.
- A security note on running untrusted code in child processes.
- At least a handful of public projects using saboteur in CI.

Exit criteria: no known correctness bugs, and an API we are willing to keep.

## Rails track

Rails and RSpec teams are the first audience. The positioning: the easiest
trustworthy pull request test-quality check for Rails and RSpec, not the tool
with the most operators. The install generator, Rails doctor and cache
fingerprint fixes are in flight as the first priority; the rest follows.

- P1: measure cold and warm CI overhead on real Rails apps. Why: the cost of
  the job is app boot, database setup, coverage and mutants, and buyers need a
  measured number, not a guess.
- P1: independent Rails and Postgres install evidence from an outside project
  on Linux CI. Why: "works on two apps" is not a compatibility claim.
- P1: Rails auto-detect config defaults (Gemfile.lock and `config/environment.rb`
  present). Why: a Rails user should not need to know the boot file or globs.
- P1: DSL-aware subject discovery for validations, scopes and associations.
  Why: discovery is `def`-only, so a lot of Rails behaviour is never mutated.
- P1: database hardening: detect an open fixture transaction before fork, and
  namespace worker databases per run. Why: today a committed write or a second
  run at the same time can corrupt results silently.
- P2: legacy baseline and ratchet UX, and reviewer-friendly output. Why: a team
  with many old survivors will not adopt a tool that fails on day one.
- P2: tested CI templates for SQLite and Postgres, and a Rails config bridge
  (`config.saboteur`, lighter than a second settings system). Why: copy-paste
  CI that works is the main way Rails tools spread.

## Outreach

Work that runs alongside the milestones:

- Keep the site and the benchmark page current with every release.
- Write up the benchmark honestly, including where mutineer wins.
- Post to Ruby Weekly and the Ruby community, and submit a talk to a Ruby
  conference such as RubyConf India once Milestone 2 is done.
- Open issues labelled "good first issue" for operators and reporters, since
  the plugin API makes them small and safe to review.

## AI-native track

Coding agents already run test commands and read their output. This track makes
saboteur safe and cheap for an agent to call after the specs pass. The
`--help` map for agents has already shipped.

- P0: a compact agent JSON projection, about 8 KiB, with the top 3 survivors
  and detail on demand, an explicit complete, partial or not-applicable status,
  and provenance. Why: the full report is too big for an agent's context, and
  an agent must not mistake a partial run for a clean one.
- P0: strict agent exit semantics: 0 only for a complete, clean run. Why: today
  mixed errors can exit 0, and an agent reads 0 as "done".
- P0: a repo-dropped agent skill or rule (`AGENTS.md` / `CLAUDE.md` trigger)
  that runs saboteur after RSpec goes green. Why: agents only use what the
  repo tells them to use.
- P1: explain a survivor by digest. Why: the agent needs the diff, the covering
  tests and a hint for one survivor, without rerunning anything.
- P1: a total-runtime budget that includes the cold coverage run. Why: an agent
  session has a time limit, and a timeout must read as incomplete, not clean.
- P1: artifact and lock safety for concurrent runs. Why: two agents in one
  checkout can overwrite each other's cache and report.
- P1: warn when untracked files fall outside the diff scope. Why: a new file an
  agent just wrote is not in `git diff`, so the run silently skips it.
- P2: a local MCP adapter with `run_diff_mutation`, `explain_survivor` and
  `replay_mutant`. Why: tool calls are more reliable than shell parsing, but
  only after the CLI contract above is stable.
- P2: an agent eval harness that scores correct tool use, useful tests written,
  false dismissals of real survivors, and token cost. Why: without it we are
  guessing whether any of this helps.

## Not planned

- Support for test frameworks other than RSpec. saboteur is deliberately
  RSpec-only. Doing one framework well beats doing two halfway. The
  `Integration::Base` interface stays public for anyone who wants to build
  their own.
- Anything that needs a hosted service to run. saboteur stays a local tool.
- Language-model generation of mutants or language-model equivalence checks
  in the core. The reason is the mission: a result must repeat for the same
  code and seed, and the core must not rely on an external model's
  repeatability. Meta's system generates few,
  targeted mutants with a model and reports that engineers accepted 73% of
  the tests it produced
  ([Foster et al., 2025](https://arxiv.org/html/2501.12862)). Its equivalence
  judge had mixed precision and recall depending on how unsure answers are
  counted and on the cases included, on one population of generated Kotlin
  code, so we draw no number from it. A plugin on the mutation source API
  may try the idea.
- For the GitHub Action: operator-matrix inputs, a silent full-scan fallback
  when the diff base cannot be found, and pull request comment bots that need
  a write token.

## Where these ideas come from

Reference list for the items above, last checked on 11 October 2026. We take ideas from papers and open source
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

## Research

Two research tracks sit beside the milestones. They are listed in priority
order.

1. **Track B: dependency-aware incremental mutation.** A complete
   input-fingerprint invalidation model, evaluated by replaying project
   history against naive caching. The paper target is the Mutation workshop,
   then ICST or ISSTA. It builds on the ResultCache design.
2. **Track A: an equivalent-mutant benchmark for MRI Ruby.** A labelled
   benchmark of equivalent and duplicate mutants across real projects, and a
   validated, guarded detector. It measures where YARV bytecode filtering
   works and where it fails.
