# Best practices

How to adopt saboteur without it becoming noise. Everything here describes
what saboteur does at commit 91f4017 on `main`. Anything that depends on an
open pull request is marked **[needs #26]** and is not available until that
pull request merges and ships in a release. Check `saboteur --help` on your
installed version before relying on it.

## Start small

Run one method first, read every survivor, and only then widen:

```sh
bundle exec saboteur run --subject 'YourClass#your_method'
```

You get counts per status, a score, and a unified diff for every survivor.
Reading real diffs for a handful of methods teaches you what the tool finds in
your code. That is worth more than a whole-project number you do not yet
trust.

Before anything else, check that your suite is green and that SimpleCov is
off for the run (see "SimpleCov" in the [README](../README.md)). Rails apps
need their boot file under `require:` in `.saboteur.yml`.

## Pick a run mode for each place

| Where | Command | Why |
| --- | --- | --- |
| Pull requests | `saboteur run --since origin/<base>` | Mutates only the methods the branch changed. Fast, and every survivor is in code the author just wrote. |
| main or nightly | `saboteur run` (no `--since`, no `--incremental`) | Diff mode does not recheck callers of a changed method, methods outside `include`, or deleted methods. A whole-project run is the only thing that covers those. |
| Your laptop | `--subject`, or `--since`, with `--jobs N` | Keep the loop short. |

Details and limits of diff mode are in
[the pull-request guide](pull-requests.md). Three things worth knowing:

- `--since` needs the ref to exist locally and enough git history to find the
  merge base. In CI that means `fetch-depth: 0`. A bad ref fails the run; it
  does not quietly fall back to a full run.
- Diff mode still builds the coverage map by running your whole suite once
  when no valid cached map exists. That fixed cost does not shrink with the
  diff, so do not expect a PR run to take seconds on a slow suite.
- Keep new files tracked in git, or the diff cannot see them.

Keep one shared `.saboteur.yml` and pass `--since` only in the PR job. A
`since:` value stored in YAML is not cleared by omitting the flag, and there
is no `--no-since`. If you want a PR-only config, make it a separate file
(`--config .saboteur-pr.yml`).

`--incremental` reuses earlier verdicts while the method, mutant, covering
tests, lockfile and config are unchanged. It cannot see a change in a method
the subject calls. Use it for local iteration, and run without it on main now
and then.

## The GitHub Action

[`docs/github-action.md`](github-action.md) is the reference. The short
version: add the workflow from that page, which runs
`saboteur run --since origin/<base>` on `pull_request` events with a read-only
token and full history.

Practical points:

- **Run it advisory first.** The default (`fail-on-survivors: "false"`) shows
  survivors as a warning and in the job summary, and the check stays green.
  Read the summaries for a few weeks before you gate anything.
- **Pin it.** Use a release tag or full commit SHA once a release containing
  the Action exists. `@main` follows development, and the docs call it a
  preview until it has been tried on an outside project.
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
- **If a cached run looks wrong, set `cache: "false"`.** The coverage-map hash
  cannot see environment variables, database fixtures or the Ruby version.
- Do not use `pull_request_target`, and do not run untrusted PR code with
  secrets. The Action refuses `pull_request_target`.

There is no pull-request comment and no baseline file yet. The job summary and
workflow warning are the report.

## Choosing and raising a threshold

**On `main` today** there is no score threshold flag. The gate is binary: with
`fail-on-survivors: "true"` (or a plain `saboteur run`, which exits 1), any
survivor not on the ignore list fails. That is strict but workable when the
diff is small, which is why it suits PRs.

**[needs #26]** `--threshold PERCENT` (or `threshold:` in `.saboteur.yml`)
makes the run exit 1 when the score is below PERCENT, even with survivors. As
written in that pull request:

- The score is `(killed + timeout) / (killed + survived + timeout)`. No
  coverage, errors and resource limits are outside it.
- It fails closed. A run that tested no mutant has no score and exits 1. A run
  where any mutant errored or hit a resource limit exits 3.
- Survivors on the ignore list still count as survived in the score, so
  ignoring a survivor does not raise the number.

If that lands as described, a sensible way to pick a number:

1. Run a whole-project audit on main and note the score.
2. Set the threshold a few points under it, so the check catches regressions
   without failing on noise.
3. Raise it when the score has stayed above it for a while. Move in small
   steps. A threshold you cannot meet is one the team learns to ignore.

Two cautions that hold either way:

- The score describes the mutants saboteur selected, not every possible
  mutation. Changing `max_mutants_per_method` or the config changes the
  denominator, so compare scores only between runs with the same settings.
- A subject with no tests is skipped before mutation, so it is not in the
  score. Adding the first test to a skipped method can lower the score. A
  score that rises because mutants disappeared has not improved test quality.
- A PR run's score on two changed methods is a small sample. A single
  survivor can swing it a lot, so do not set a tight percentage on PR runs.

Timeouts count as detected. A loop-heavy change can pass by timing out. A
limit on timeouts is on the [roadmap](../ROADMAP.md) but does not exist.

## Handling surviving mutants

Every survivor is printed with a diff and a digest. Each needs a human look.
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

```yaml
# .saboteur-ignore.yml
- subject: "Billing::Invoice#total"
  mutation: "1a2b3c4d5e6f7a8b"
  reason: "equivalent: amounts are always whole cents"
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
- **Unchanged-method check.** After a method's mutants run, saboteur re-runs
  the killing tests against the unmodified method. If they fail there too, the
  kill is not credited. It becomes an error and is counted as a rejected kill
  (`kills rejected by unchanged-method check: N` in the terminal,
  `rejectedKills` in JSON). Treat a non-zero count as a sign of flaky or
  order-dependent tests, and fix those tests first. Details are in
  [rejected kills](rejected-kills.md).
- **Resource limits.** Each mutant runs in a supervised child with deadline,
  memory and process limits. A mutant that loops forever becomes a timeout.

What it does not do: there is no flaky-test guard that refuses to start on an
unstable suite yet. It is listed as planned in the [roadmap](../ROADMAP.md).
So, before a first run and after any change to your suite:

- Run your suite a few times and with the same seed. If it is not green every
  time, fix that before measuring anything.
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

There is no baseline file yet ("accept today's survivors, fail only on new
ones" is on the [roadmap](../ROADMAP.md)). Until it exists, ratchet using what
is there:

1. **Diff mode only, advisory.** Add the Action on pull requests with the
   default advisory setting. Code a PR touches is code someone is already
   reading, so survivors there are cheap to act on. You never face the whole
   backlog.
2. **Pick a few modules and cover them well.** Use `--subject` on a
   namespace, or `include` / `exclude` in `.saboteur.yml`, to start with the
   code you care about most (billing, auth). Get those clean, then widen
   `include`.
3. **Run a full audit on a schedule.** A nightly or weekly `saboteur run` on
   main gives you a score trend without blocking anyone. Set the same config
   each time so the numbers are comparable.
4. **Triage once, record the decisions.** Put accepted survivors in
   `.saboteur-ignore.yml` with reasons, so every later run starts from the
   decisions you already made.
5. **Then enforce on PRs.** Once PR summaries have been quiet for a while, set
   `fail-on-survivors: "true"`. saboteur's own CI does this. Because PR runs
   cover only changed methods, legacy code you did not touch does not block
   anyone.
6. **Ratchet.** After the nightly score is stable, **[needs #26]** add a
   `--threshold` a little under it and raise it as the number rises. Never
   lower it without saying why in the change. Whether the Action accepts
   `--threshold` through its `arguments` input has not been verified here;
   check the Action docs after #26 ships.

## Local workflow tips

- Iterate on the thing you are changing: `--subject 'Klass#meth'`, or
  `--since origin/main` for a branch.
- Use `--jobs N` to run mutants in parallel. Results are meant to match a
  single worker.
- Use `--incremental` while you iterate, and run without it before you push.
- The HTML report at `.saboteur/report.html` (one file, no scripts, no
  network) is easier to read than terminal diffs for a long list. The JSON
  report is `.saboteur/report.json`.
- Exit codes: 0 no survivors, 1 survivors, 2 bad configuration, 3 the tool
  failed. Check them in scripts.
- If results look stale or odd, run once with `--no-cache` to rebuild the
  coverage map.
- **[needs #26]** An explicit run mode: name the files to mutate and the specs
  to run, so a local loop does not depend on `include` or a git diff:

  ```sh
  bundle exec saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb
  bundle exec saboteur run --threshold 90
  ```

  As written in that pull request, positional arguments are Ruby files or
  directories that must exist (a typo exits 2), and they replace `include`
  and `exclude`. `--test` is repeatable, needs at least one source, and
  replaces only the spec files RSpec runs. `--threshold` is described above.
  Confirm both with `saboteur --help` once released.
