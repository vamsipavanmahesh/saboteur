# saboteur vs mutineer: small-scale benchmark report

Date: 2026-10-10 (IST). saboteur 0.1.0 (commit 2b6ec02, frozen), mutineer 1.6.0.
Apple M3 Max, 14 cores, 36 GB, macOS 14.3. Ruby 3.4.3 (gems,
human-essentials) and 4.0.0 (lobsters).

Scope: every section of the brief, at small scale, by maintainer decision
(time budget about 2.5 hours). One run per configuration. Every number is
measured unless marked "estimate", and every number is indicative: a sample
of a few files, not a full benchmark. Setup, targets and mappings are in
PHASE0.md and PHASE1.md; raw data is in raw/.

## Summary

| Metric | saboteur | mutineer | Winner | Notes |
|---|---|---|---|---|
| Fake kills (lobsters) | 0 of 20 sampled kills | at least 8 of 91 kills; 8 of 8 checked | saboteur | Section 1. mutineer scored 100% on lobsters; the 8 checked "kills" survive the whole suite |
| Kills refused by its own check | 3 (one order-dependent test) | none (no such check) | saboteur | saboteur re-runs the killing tests with the code unchanged |
| Real bugs detected | 0 of 3 | 0 of 3 | tie | All 3 fixes add missing code; neither tool can generate that. Too few to judge |
| Useful survivors (blind, 10 each) | 5 useful, 4 equivalent, 1 noise | 4 useful, 1 equivalent, 5 noise | saboteur, slightly | Three reviewers; section 3 |
| Speed, hashie, 6 workers | 1,580 mutants in 10.8 s | 409 mutants in 34.9 s | saboteur | 0.008 vs 0.092 s per mutant run |
| Speed, hashie, matched operators | 1,267 mutants (filter) in 10.8 s | 1,271 mutants in 70.3 s | saboteur | Closest like-for-like count |
| Speed, lobsters, 1 worker | 231 mutants in 442 s (1.9 s each) | 95 mutants in 219 s (2.4 s each) | saboteur, per mutant | mutineer's lobsters kills are partly fake, so its time is not like-for-like |
| Parallel on RSpec Rails | yes: lobsters 442 s to 125 s at 6 workers, same verdicts | no: `--daemon` is Minitest-only | saboteur | |
| Runs on human-essentials (Postgres) | yes: item.rb, 98 mutants, 520 s | no, after 5 tries (about 1 h 50 min) | saboteur | Section 2 |
| Serial vs parallel agreement | 231 of 231 identical (lobsters) | hashie: summary counts differ by one (333 killed and 1 timeout at 6 workers; 332 and 2 at 1 worker) | saboteur | mutineer compared by counts only |
| Peak memory | 595 MB (hashie, 6 workers); 4,261 MB (lobsters, 6 workers) | 471 MB (hashie, 6 workers); 775 MB (lobsters, 1 worker) | mutineer | saboteur's parallel Rails run uses a full app copy per worker |
| Leftover processes | 0 in every run | 0 in every run | tie | DB connections were not measured |
| Setup effort | 1 workaround (fiddle on Ruby 4.0) | 2 environment variables and 6 spec files removed for human-essentials | saboteur | |
| Operators | 14 operators, one fixed set | 20 operators, 5 default, chosen with `--operators` | mutineer | |
| CI and reporting features | Stryker JSON, ignore list, diff mode, incremental cache | JSON, HTML, baseline, threshold, GitHub Action, inline disable, `--matrix` | mutineer | Section 7 |
| Minitest | no (out of scope by design) | yes | n/a | Not scored |

## Every place mutineer won

1. Peak memory, measured before the fork-memory work (the paired before and after on
   hashie is in Result 6 of the benchmark page): lower in every pair measured (471 vs 595 MB on hashie; 775 MB
   at 1 worker vs saboteur's 1,021 MB at 1 worker on lobsters).
2. Operator choice: 20 operators and a switch to pick them; saboteur has no
   operator selection.
3. CI features: baseline gating, score threshold, GitHub Action with PR
   annotations, HTML report, inline `# mutineer:disable-line`, `--matrix`
   for blind and redundant tests, documented stable mutant ids.
4. Zero runtime dependencies; saboteur needs fiddle on Ruby 4.0 and does not
   declare it (saboteur bug).
5. Fewer survivors to read: its default set made 409 mutants on hashie
   against saboteur's 1,580, so a user has 47 survivors to review instead
   of 177. (This is also less coverage of the code.)
6. Safety stance: it refuses to score when a covering spec file fails on its
   own. That stopped it on human-essentials, but it is a defensible rule.

## 1. Correctness

Method: raw/fake-kill/.

- mutineer's `--matrix` run on lobsters (domain.rb, origin.rb, tag.rb)
  reported 91 kills, each with no killing test and 0 tests run. So no kill
  could be attributed to a test.
- Instead, 8 mutants that both tools made identically were applied by hand,
  one at a time, and the whole lobsters suite (899 examples) was run each
  time. These were statement removals on the same line with the same
  replacement. All 8 runs passed with 0 failures: no test catches any of
  these mutants. mutineer reported all 8 as killed; saboteur reported all 8
  as survived. So at least 8 of mutineer's 91 lobsters kills are fake, and
  its 100% score there is inflated. The cause was not found: `--verbose`
  printed nothing.
- saboteur: 20 kills sampled at random from its lobsters run. All 43 of
  their killing tests pass on unchanged code: 0 fake.
- saboteur's verdict check turned 3 kills into errors, all from one
  order-dependent test (spec/features/submit_story_spec.rb[1:10], "Domain
  has already been taken").
- Repeatability (run 1 vs run 2): not measured; one run each.
- Serial vs parallel: saboteur lobsters, 231 of 231 verdicts identical at
  1 and 6 workers. mutineer hashie, 1 and 6 workers: summary counts differ
  by one (one more timeout, one fewer kill at 1 worker); per-mutant
  comparison not done.
- Leftover processes: 0 after every run (watchdog). DB connections: not
  measured.

## 2. Running on each target

| Target | saboteur | mutineer |
|---|---|---|
| hashie (full) | ran | ran |
| addressable template.rb | ran | ran |
| lobsters (3 models, SQLite, Ruby 4.0) | ran at 1 and 6 workers | ran at 1 worker only (`--daemon` rejects RSpec) |
| human-essentials item.rb (Postgres) | ran: 98 mutants, 85 killed, 11 survived, 2 no coverage, 520 s, 1 worker | did not run |

mutineer on human-essentials, in order: coverage capture crashed 428 times
(Objective-C fork-safety abort, macOS); fixed with
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES and PGGSSENCMODE=disable. It then
refused three times because covering spec files fail on their own; 6 such
files were found and removed for both tools. The last two tries failed with
"the unmutated suite is not green (combined suite)" after different spec
files failed coverage capture each time. Logs: raw/findings/.

mutineer strategies: on lobsters tag.rb, `reload` gave the same counts as
the default `redefine` (11 mutants, 9 killed, 2 no coverage; 207.5 s vs
192 s).

## 3. Usefulness of survivors (blind)

Method: 10 survivors per tool from hashie, picked at random (seed
20261010), mixed, with tool names hidden. Two Claude reviewers and Grok
labelled all 20 independently: actionable, equivalent or noise. They agreed
pairwise on 14 to 18 of 20 items. The 6 split items were resolved by
reading the code before unblinding. Data: raw/usefulness-labels.json and
raw/usefulness-items.md.

| | actionable | equivalent | noise |
|---|---|---|---|
| saboteur | 5 | 4 | 1 |
| mutineer | 4 | 1 | 5 |

mutineer's noise is mostly statement removals that change nothing worth
testing. saboteur's misses are more often equivalent mutants. With 10 each,
a gap of one useful survivor is not meaningful.

## 4. Real bug detection

Three hashie bug fixes that change lib/ and add a test: 3988742, 043aa89,
e295a0d. Each tool ran on the pre-fix file with the pre-fix specs. A bug
counts as detected if a survivor lands within 2 lines of a line the fix
changed. Data: raw/bug-*.json.

| Fix | What the fix did | Mutation-detectable | saboteur | mutineer |
|---|---|---|---|---|
| 3988742 | `dup` to deep dup | no (no operator removes or changes `dup`) | not detected | not detected |
| 043aa89 | add constructor arguments | no (missing code) | not detected | not detected |
| e295a0d | add a branch | no (missing code) | not detected | not detected |

For e295a0d, two 2021-era spec files fail on Ruby 3.4 and were removed for
both tools. mutineer correctly refused to run with them.

## 5. Speed and resources

Wall time includes boot and coverage capture, with cold caches.

| Run | Tool | Workers | Mutants | Killed | Survived | Wall | s per mutant run | Peak RSS |
|---|---|---|---|---|---|---|---|---|
| hashie | saboteur | 6 | 1,580 | 1,172 | 177 | 10.8 s | 0.008 | 595 MB |
| hashie | mutineer | 6 | 409 | 333 | 47 | 34.9 s | 0.092 | 471 MB |
| hashie, matched | mutineer | 6 | 1,271 | 986 | 186 | 70.3 s | 0.060 | 519 MB |
| hashie | saboteur | 1 | 1,580 | 1,172 | 177 | 31.6 s | 0.023 | 266 MB |
| hashie | mutineer | 1 | 409 | 332 | 47 | 2,640 s | 6.9 | 148 MB |
| addressable template.rb | saboteur | 6 | 435 | 342 | 84 | 7.7 s | 0.018 | 535 MB |
| addressable template.rb | mutineer | 6 | 172 | 145 | 21 | 14.9 s | 0.090 | 547 MB |
| lobsters, 3 models | saboteur | 1 | 231 | 166 | 47 | 442 s | 2.0 | 1,021 MB |
| lobsters, 3 models | saboteur | 6 | 231 | 166 | 47 | 125 s | 0.58 | 4,261 MB |
| lobsters, 3 models | mutineer | 1 | 95 | 91 | 0 | 219 s | 2.4 | 775 MB |

The mutineer hashie run at 1 worker (2,640 s) is unexplained. A small file at
1 worker was normal (13 s), so this needs a repeat before anyone relies on
it.

Time to first survivor, time per subject and diff-mode timing: not measured.

CI cost, estimate. GitHub's standard Linux 2-core runner costs $0.006 per
minute, billed in whole minutes
([source](https://docs.github.com/en/billing/reference/actions-runner-pricing)).
Assuming a 2-core runner does about twice the work of the 1-worker times
above:

| Run | saboteur | mutineer |
|---|---|---|
| hashie, full | 1 min, $0.006 | 2 min, $0.012 (from the 6-worker time) |
| lobsters, 3 models | 4 min, $0.024 | 4 min, $0.024 |

Real suites cost more. These figures only show that both tools are cheap at
this size.

## 6. Coverage of Ruby

Not measured by construct. The operator tables in PHASE1.md show the
difference in kind. mutineer covers collections, regexes, ranges, literals,
chains and `&&`/`||` swaps that saboteur does not. saboteur covers
whole-method mutants (nil, true or false, raise) and `||=` that mutineer
does not.

## 7. Features

| Feature | saboteur | mutineer |
|---|---|---|
| Diff mode (`--since`) | yes | yes |
| Baseline (fail only on new survivors) | no | yes |
| Score threshold exit code | no | yes |
| Ignore list with reasons | yes (.saboteur-ignore.yml) | yes (ids in .mutineer.yml, inline comments) |
| Stable mutant ids | yes | yes (documented) |
| Report formats | terminal, Stryker JSON | human, JSON, HTML |
| GitHub Action | no | yes |
| Rails parallel on SQLite | yes | Minitest only |
| Rails parallel on Postgres | yes | no |
| Kill verification | yes (re-runs killing tests on unchanged code) | no |
| Per-example test selection | yes | no (per spec file) |
| Memory, process and CPU caps per mutant | yes | no (wall-clock timeout only) |
| Blind or redundant test report | no | yes (`--matrix`) |
| RSpec | yes | yes |
| Minitest | no (out of scope by design) | yes |

Report readability (opinion): mutineer's human report is short and its JSON
is well documented. saboteur prints a diff per survivor, which reads well,
but its Stryker JSON needs a viewer to be pleasant.

## Limitations

- One run per configuration: no ranges and no repeatability numbers.
- Rails apps were sampled: 3 lobsters models and 1 human-essentials model.
- Fake kills: mutineer was checked on 8 identical mutants, not a random
  sample, because its report names no killing tests. saboteur was checked
  on 20 random kills.
- Only 3 real bugs, none of them mutation-detectable.
- 10 survivors per tool for usefulness.
- Not measured: diff-mode timing, time to first survivor, coverage by
  construct, DB connections after runs.
- macOS only. mutineer's human-essentials failures may not happen on Linux
  CI.

## Build vs contribute

From this data, saboteur is meaningfully different in three ways that
matter on real RSpec Rails apps:

1. It verifies kills. mutineer's lobsters score was inflated by kills that no
   test makes. This is the largest difference found, and it changes whether
   a mutation score can be trusted.
2. It runs RSpec Rails apps in parallel, on SQLite and Postgres, with
   identical verdicts. mutineer runs them on one worker, and did not run on
   the Postgres app at all.
3. It is several times faster per mutant on the gems (per-example selection
   and forking from a warm process).

Each of these could in principle be contributed to mutineer. Kill
verification and per-example selection would be deep changes to how
mutineer runs and judges mutants (it judges by the test runner's exit code
and selects whole files). RSpec support in `--daemon` and Postgres worker
databases are smaller, self-contained contributions. mutineer is ahead on
product features (CI gating, HTML, Action, operator choice), and saboteur
would have to build those.

A reasonable path: keep saboteur as the RSpec-focused engine, and file the
upstream issues (upstream-issues.md) so mutineer users get the fixes. Treat
the fake-kill finding as the headline to confirm with a larger sample
before making public claims.

## Reproducing

`run_all` regenerates every number in this report from pinned targets:
setup notes are in PHASE0.md, and the scripts are run_one, gems_small,
rails_and_bugs_small, bugs_small, overlap_check.py, fake_kill_check.py,
fake_kill_run, summarize.py and bug_detect.py.
