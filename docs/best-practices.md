# Best practices

How to adopt saboteur without it becoming noise. Everything here describes
behavior available in the released v0.7.0 gem; it intentionally leaves out
changes that are still unreleased on `main`. Check `saboteur --help` on your
installed version before relying on a flag.

## Start small

Run one method first, read every survivor, and only then widen:

```sh
bundle exec saboteur run --subject 'YourClass#your_method'
```

You get counts per status, a covered score, and the exact surviving changes
to review. Reading real survivors for a handful of methods teaches you what
the tool finds in your code. That is worth more than a whole-project number
you do not yet trust.

Before anything else, check that your suite is green and that SimpleCov is
off for the run (see "SimpleCov" in the [README](../README.md)). Rails apps
need their boot file under `c.require` in `config/saboteur.rb`.

## Pick a run mode for each place

| Where | Command | Why |
| --- | --- | --- |
| Pull requests | `saboteur run --since origin/<base>` | Mutates only the methods the branch changed. Fast, and every survivor is in code the author just wrote. |
| main or nightly | `saboteur audit` | Runs the whole configured scope with all operators, both baseline checks and both reports. Diff mode does not recheck callers of a changed method, methods outside `include`, or deleted methods. |
| Your laptop | `--subject`, or `--since`, with `--jobs N` | Keep the loop short. |

Details and limits of diff mode are in
[the pull-request guide](pull-requests.md). Three things worth knowing:

- `--since` needs the ref to exist locally and enough git history to find the
  merge base. In CI that means `fetch-depth: 0`. A bad ref fails the run; it
  does not quietly fall back to a full run.
- Diff mode still builds a coverage map from the inferred or named specs
  when no valid cached map exists (`--all` uses the whole suite). That fixed
  cost comes before mutation, so do not expect every PR run to take seconds
  on a slow suite.
- An untracked Ruby file inside the configured `include` set counts as fully
  changed. A new file outside `include` is not seen until you add it there.

Keep one shared `config/saboteur.rb` and pass `--since` only in the PR job. A
`c.since` value stored in the config is not cleared by omitting the flag, and
there is no `--no-since`. If you want a PR-only config, make it a separate
file (`--config config/saboteur_pr.rb`).

`--incremental` reuses an earlier verdict while the method, its whole file,
the mutant, its covering tests and their files, the lockfile and the config
are unchanged. It cannot see a change in another file that the subject uses.
Use it for local iteration, and run without it on main now and then.

`--incremental` also saves verdicts while the run is going (about every 30
seconds), not only at the end. If a long run is killed by a timeout or an
out-of-memory kill, the next run with `--incremental` picks up the verdicts
that were already saved. These mid-run saves are best effort: if one fails,
for example on a full disk, the run keeps going and tries again later. The
save at the end of the run still fails loudly.

## The GitHub Action

[`docs/github-action.md`](github-action.md) is the reference. The short
version: add the workflow from that page, which runs diff mode on
`pull_request` events with a read-only token and fetches only enough history
to prove the merge base.

Practical points:

- **Run it advisory first.** The default (`fail-on-survivors: "false"`) shows
  survivors as annotations, a warning and a job summary, and the check stays
  green. Read the summaries for a few weeks before you gate anything.
- **Pin it.** Use a release tag such as `v0.7.0` or a full commit SHA.
  `@main` follows development.
- **Your setup stays in your workflow.** The Action does not install Ruby or
  gems. Database, boot files and the SimpleCov guard are yours to configure.
- **Setup errors always fail the step.** Exit 2 (bad config) and exit 3 (tool
  failure, or a missing or malformed report) fail even in advisory mode.
- **`fail-on-survivors: "true"` also fails on incomplete runs**, meaning some
  mutants errored or hit a resource limit. Those mutants are not scored, so
  do not read a green check as "everything was tested" unless the
  `incomplete` output is false.
- **Do not trust the PR score as a project score.** It covers only the
  selected methods, capped at `max_mutants_per_method` per method.
- **If a cached run looks wrong, set `cache: "false"`.** saboteur's map
  fingerprint covers declared fixtures and config, but the Action's restore
  key does not include environment variables or the Ruby version.
- Do not use `pull_request_target`, and do not run untrusted PR code with
  secrets. The Action refuses `pull_request_target`.

There is no pull-request comment; annotations, the job summary and the
workflow warning are the report, and the JSON report is uploaded as an
artifact when the run produces one. A baseline gate exists, but it is a
whole-project check: use it on main or a schedule, not as a replacement for
the PR diff run. See the Action reference for the `baseline` and
`baseline-epsilon` inputs.

## Choosing and raising a threshold

Without a threshold, the gate is binary: any survivor not on the ignore list
fails the run. That is strict but workable when the diff is small, which is
why it suits PRs.

`--threshold PERCENT` (or `c.threshold` in `config/saboteur.rb`) makes the run
exit 1 when the covered score is below PERCENT, even with survivors:

- The covered score is `(killed + timeout) / (killed + survived + timeout)`.
  No coverage, errors and resource limits are outside it.
- It fails closed. A run that tested no mutant has no score and exits 1. A
  run where any mutant errored or hit a resource limit exits 3.
- Survivors on the ignore list still count as survived in the score, so
  ignoring a survivor does not raise the number.

Per-path score gates hold one subtree to a stricter floor than the rest
(#473). In `config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.score_gate "app/payments/**/*", min_score: 95
end
```

Each gate scores only the mutants under its pattern, with the same formula
as `--threshold`, and fails the run under its floor. A gate whose pattern
matches no executed mutant passes vacuously and says so on stderr. Like
`--threshold`, score gates cannot combine with `--agent`.

A sensible way to pick a number:

1. Run a whole-project audit on main and note the score.
2. Set the threshold a few points under it, so the check catches regressions
   without failing on noise.
3. Raise it when the score has stayed above it for a while. Move in small
   steps. A threshold you cannot meet is one the team learns to ignore.

Three cautions:

- The score describes the mutants saboteur selected, not every possible
  mutation. Changing `max_mutants_per_method` or the config changes the
  denominator, so compare scores only between runs with the same settings.
- A subject with no tests is skipped before mutation, so it is not in the
  score. Adding the first test to a skipped method can lower the score. A
  score that rises because mutants disappeared has not improved test quality.
- A PR run's score on two changed methods is a small sample. A single
  survivor can swing it a lot, so do not set a tight percentage on PR runs.

Timeouts count as detected, so a loop-heavy change can pass by timing out.
Use `--max-timeouts N` (or a percentage such as `--max-timeouts 5%`) when that
would hide a problem. `--max-errors N` does the same for errored mutants.
Both gates fail the run above the limit and are meant for CI.

## Handling surviving mutants

Every survivor is printed with a diff and a digest. Each needs a human look.
For a worked example, see [How to read survivors](guides/reading-survivors.md).
A survivor is one of four things:

1. **A missing test.** The most common and the point of the tool. Write the
   test.
2. **An equivalent mutant.** The change does not alter behavior, so no test
   could notice it (for example `x >= 0` to `x > 0` where `x` is never
   zero). Accept it on the ignore list with a reason.
3. **A flaky or order-dependent test.** See the next section.
4. **A limit of the tool.** Report it, and ignore the entry with a reason that
   says so.

A workable triage order:

1. Read the diff and ask: if the code really did this, would a user or caller
   notice? If yes, it is a missing test.
2. Check whether the method has any test that exercises the changed line.
   A "no coverage" result is different from a survivor: no test reaches it, so
   it needs a test before mutation says anything useful.
3. Write the smallest test that fails against the mutated code and passes
   against the real code. Assert the behavior (a return value, a side effect),
   not the implementation.
4. Only when you can explain, in one sentence, why no test could tell the two
   versions apart, accept it.

**Write a test when** the mutant changes something observable, such as a
return value, a raised error, a boundary, a persisted record or a branch.
**Justify and ignore when** the change is equivalent, or the only way to
detect it is a test that would be a copy of the implementation.

Accepting a survivor:

```ruby
# config/saboteur_ignore.rb
Saboteur.ignore do |i|
  i.mutation "1a2b3c4d5e6f7a8b",
             subject: "Billing::Invoice#total",
             reason: "equivalent: amounts are always whole cents"
end
```

An entry without a reason is rejected. Make the reason specific enough that a
reviewer can disagree with it. "Not worth testing" is not a reason; "equivalent:
the loop bound is never reached because the list is capped at 10" is. Review
the ignore file in code review like any other change, and revisit entries when
the method changes. If a method changes a lot, check that its entries still apply.

Do not tune tests to the mutants. If a survivor tempts you to add an assertion
that just restates the code, the method may be better off simplified.

## Flaky-test hygiene

saboteur decides a mutant is killed when a covering test fails. A flaky test
can therefore produce a false kill, and an order-dependent one can hide a real
survivor. What the tool does for you today:

- **Fixed seed.** Every test run starts from the same Ruby random seed
  (default 1). Tests that use `rand` see the same values in each mutant's run
  and in the confirming run. The report prints the seed; pass `--seed N` to
  repeat a run.
- **Baseline passes.** Every run with selected subjects checks the unchanged
  suite first, twice by default. Both passes must be green, complete and in the same RSpec
  order at the run seed. `saboteur doctor --suite` runs the same kind of setup
  check without mutating. Setting `c.baseline_passes = 1` is faster, but gives
  up the order-stability comparison. Use 1 for pull request runs (the `pr`
  preset already does this) where speed matters most, and keep 2 on main so
  the second pass can catch an unstable test order before it corrupts a score.
- **Unchanged-method check.** After a method's mutants run, saboteur re-runs
  the killing tests against the unmodified method. If they fail there too, the
  kill is not credited. It becomes an error and is counted as a rejected kill
  (`kills rejected by unchanged-method check: N` in the terminal,
  `rejectedKills` in JSON). Treat a non-zero count as a sign of flaky or
  order-dependent tests, and fix those tests first. Details are in
  [rejected kills](rejected-kills.md).
- **Resource limits.** Each mutant runs in a supervised child with deadline,
  memory and process limits. A mutant that loops forever becomes a timeout.

Two passes detect observed instability, not every possible flaky test. So,
before a first run and after any change to your suite:

- If the baseline or doctor suite check is not green every time, fix that
  before measuring anything.
- Remove time, randomness and ordering dependencies from the tests that cover
  the code you mutate. Freeze time, seed random data, and clean the database
  between examples.
- Treat errors in the summary as signals, not noise. Errors are not scored
  and, in the Action, an incomplete run fails when `fail-on-survivors` is on.
- If a test is flaky and you cannot fix it now, quarantine it with your normal
  RSpec tooling and keep that visible, rather than letting it quietly
  produce kills.

## Adopting on a legacy codebase

Do not start with a whole-project run and a hard gate. On a large codebase
the first number will be low, and a failing check on day one gets the tool
switched off.

A baseline now exists, but it is a reviewed whole-project gate, not a way to
skip today's survivors silently. Ratchet in stages:

1. **Diff mode only, advisory.** Add the Action on pull requests with the
   default advisory setting. Code a PR touches is code someone is already
   reading, so survivors there are cheap to act on. You never face the whole
   backlog.
2. **Pick a few modules and cover them well.** Use `--subject` on a
   namespace, or `c.include` / `c.exclude` in `config/saboteur.rb`, to start with the
   code you care about most (billing, auth). Get those clean, then widen
   `include`.
3. **Run a full audit on a schedule.** A nightly or weekly `saboteur audit`
   on main gives you a score trend without blocking anyone. Set the same
   config each time so the numbers are comparable.
4. **Triage once, record the decisions.** Put accepted survivors in
   `config/saboteur_ignore.rb` with reasons, so every later run starts from the
   decisions you already made.
5. **Then enforce on PRs.** Once PR summaries have been quiet for a while, set
   `fail-on-survivors: "true"`. saboteur's own CI does this. Because PR runs
   cover only changed methods, legacy code you did not touch does not block
   anyone.
6. **Add a baseline on main when review needs it.** Run `baseline propose`,
   give every survivor a review reason, run `baseline accept`, and commit the
   baseline. A scheduled Action run can then use `baseline` and
   `baseline-epsilon`. The check runs the whole project, so keep the cheaper
   diff run on PRs.
7. **Ratchet the score.** After the scheduled score is stable, add a
   `--threshold` a little under it and raise it as the number rises. Never
   lower it without saying why in the change. The Action accepts extra flags
   through `arguments`; check its reference before adding a gate.

## Local workflow tips

- Iterate on the thing you are changing: `--subject 'Klass#meth'`, or
  `--since origin/main` for a branch.
- Use `--jobs N` to run mutants in parallel. Results are meant to match a
  single worker.
- Use `--incremental` while you iterate, and run without it before you push.
- The HTML report at `.saboteur/report.html` (one file, no scripts, no
  network) is easier to read than terminal diffs for a long list. The JSON
  report is `.saboteur/report.json`.
- Exit codes: 0 pass, 1 survivors or a failed score/error limit, 2 bad
  configuration or input, 3 tool failure or incomplete run, 4 text-mode run
  budget exhausted. Check them in scripts.
- If results look stale or odd, run once with `--no-cache` to rebuild the
  coverage map.
- For an explicit local loop, name the files to mutate and the specs to run,
  so the run does not depend on `include` or a git diff:

  ```sh
  bundle exec saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb
  bundle exec saboteur run --threshold 90
  ```

  Positional arguments are Ruby files or directories that must exist (a typo
  exits 2), and they replace `include` and `exclude`. `--test` is repeatable,
  needs at least one source unless `--since` supplies the changed files, and
  replaces only the spec files RSpec runs.
