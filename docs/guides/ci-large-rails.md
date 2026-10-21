# saboteur in CI on large Rails apps

The setup that works on a big suite: fast diff-mode runs on every pull
request, a scheduled whole-project audit, and a cache that keeps both cheap.
Every knob below is covered in the [GitHub Action guide](../github-action.md)
and the [pull-request guide](../pull-requests.md); this page puts them in one
place for a large app.

## The shape

- **On each pull request:** diff mode. saboteur mutates only the methods the
  branch changed and runs only the specs that cover them. A green PR run says
  "the code this PR touched is tested", not "the project is tested".
- **On a schedule (nightly or weekly):** the whole project, so untouched code
  is measured too. This is where the score for the whole app comes from.

## Pull-request runs

Use the bundled Action; it runs diff mode against the PR's recorded base
commit and is advisory by default:

```yaml
name: Mutation testing
on: pull_request
permissions:
  contents: read
jobs:
  mutation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with:
          fetch-depth: 1
      - uses: ruby/setup-ruby@14594264cd68ce8a2345dd349bc3d138a4ef85c8 # v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - uses: vamsipavanmahesh/saboteur@main
```

Pin the action to a release tag or full SHA once a release carries it.

Without the Action, the same run by hand:

```sh
git fetch origin main
bundle exec saboteur pr
```

The `pr` preset is `--since main --baseline-passes 1 --max-duration 10m`:
changed lines since `main`, one unchanged-suite check instead of two, and a
ten-minute wall-clock budget whose exhaustion fails the run with exit 4 -
pass `--max-duration-ok` explicitly to accept the partial verdict. Explicit
flags after the preset win.

### Keeping PR runs fast on a large app

- Diff mode already scopes subjects to the diff. Since 0.7.0 the run also
  infers the specs named after the mutated files and runs only those,
  baseline passes included. A changed file with no conventional spec stops
  with exit 2 and names the ways out (`--test` or `--all`), so CI never
  silently mutates untested new code.
- `--jobs N` runs workers in parallel. With Rails, `--jobs` above 1 needs
  PostgreSQL or SQLite: the first worker keeps the test database and each
  extra worker gets its own copy named for saboteur. Other adapters (MySQL)
  keep `--jobs 1`.
- Keep the SimpleCov guard: saboteur needs Ruby's `Coverage` for itself, so
  key SimpleCov to an environment variable that CI does not set for the
  mutation job.
- `--max-duration 10m` bounds the wall clock. A spent budget stops before the
  next subject, reports partial evidence, and exits 4 unless
  `--max-duration-ok` leaves the exit to the verdict.
  A budget too small for a cold coverage build stops before it starts; see
  [the baseline stability check](../baseline-stability.md#time-budget-and-the-cold-coverage-build).

## Caching

The Action caches the coverage map files (`.saboteur/coverage-*.json`) and
nothing else - not reports, logs or `--incremental` verdicts. The map's name
contains a hash of the files it was built from, so editing a source file,
spec file or `config/saboteur.rb` rebuilds it automatically; the Action's
cache key hashes `Gemfile.lock`, `config/saboteur.rb`,
`config/saboteur_custom_map.rb` and `config/saboteur_ignore.rb`, plus the
runner OS and the commit, and restores the newest earlier entry with the
same prefix. A rebuild runs the specs selected for the
run once - the inferred specs in diff mode, the whole suite with `--all`.

If a run looks wrong, one run with `cache: "false"` rebuilds from scratch.
Do not leave it off: the map is the most expensive artifact saboteur builds.

Jobs that call `bundle exec saboteur` directly (the shards and the scheduled
audit below) are outside the Action, so cache `.saboteur/` yourself with
`actions/cache`: key on the runner OS, `Gemfile.lock` and a hash of
`config/saboteur.rb`, with a restore-key prefix so a slightly stale map is
still reused. The map's own content hash still protects you from a stale
restore - editing a listed input file rebuilds it.

## Sharding a whole-project run

Use `--shard K/N` to spread one planned inventory over several jobs. The
bundled Action runs only on `pull_request` events, so shard with plain run
steps:

```yaml
strategy:
  matrix:
    shard: [1, 2, 3]
steps:
  # ... checkout, Ruby, database setup, actions/cache for .saboteur ...
  - run: bundle exec saboteur run --all --shard ${{ matrix.shard }}/3 --max-duration 45m
  - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
    with:
      name: saboteur-report-shard-${{ matrix.shard }}
      path: .saboteur/report.json
```

`upload-artifact` rejects a second upload under one name, so the per-leg
`name` is required, not cosmetic. Run every shard on the same commit with the
same source scope, config and seed; each report prints the planned count and
an inventory digest that should match across the legs. Each shard report is
partial by design, and saboteur does not merge the reports into one score.
The [deterministic shards guide](sharding.md) covers the report fields and
boundaries.

Keep legs coarse enough to amortize their cost: every leg still runs the
baseline and coverage work for its selected scope before mutants start.
Every leg must run on the same commit: the coverage map and verdicts are
per-tree.

## The scheduled audit

```yaml
on:
  schedule:
    - cron: "17 3 * * *"
```

Whole-project runs cost the most; run them on a schedule, not per PR. The
`audit` preset is `--all --operators all --baseline-passes 2 --json
.saboteur/audit-report.json --html .saboteur/audit-report.html`. Note that
the bundled Action runs only on `pull_request` events; schedule the audit as
a plain script step or with `saboteur baseline check` (below).

## From advisory to enforced

1. Run advisory until the survivor list is familiar.
2. Record accepted survivors in `config/saboteur_ignore.rb`, each with a
   reason; entries without a reason are rejected. The ignore list changes the
   exit code, not the score.
3. Set `fail-on-survivors: "true"` on the PR job. saboteur's own CI does
   this.
4. For a gate that fails only on *new* survivors, accept today's once with
   `saboteur baseline propose` + `saboteur baseline accept`, commit the
   baseline, and set the Action's `baseline` input (optionally
   `baseline-epsilon`). Unlike the diff-mode run, the baseline check runs on
   any event except `pull_request_target`, so it fits the scheduled job.

## Exit codes to branch on

`0` clean, `1` survivors to review, `2` usage or configuration (including a
changed file with no conventional spec), `3` tool failure or an incomplete
run, `4` the `--max-duration` budget stopped the run. The Action fails the
step on 2 and 3 even in advisory mode; the full contract is the
[stability policy](../stability.md).
