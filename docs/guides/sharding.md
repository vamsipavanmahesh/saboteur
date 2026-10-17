# Deterministic shards

`--shard K/N` runs one deterministic slice of the candidate inventory.
Use it when one whole-project or large diff run is too slow for one CI job.

```sh
bundle exec saboteur run --all --shard 1/4
```

`K` is the 1-based shard to run and `N` is the total number of shards. A
valid pair has `1 <= K <= N` and at least two shards. The flag cannot be
combined with a replay (`--id`): replay names one exact mutant, while a shard
is a planned inventory.

## How candidates are assigned

saboteur first builds the same candidate inventory it would run without
`--shard`, including the usual source, subject, diff and config selection.
Each planned mutant is assigned by a SHA-256 hash of its candidate identity,
not by its position in a list. Adding or removing a mutant earlier in the
project does not shift every later mutant to another shard.

The split is deterministic, not positional and not guaranteed to be equal.
Run every shard from `1/N` through `N/N` on the same commit with the same
source scope, config and seed to cover the same inventory.

## CI matrix

Give every matrix leg the same command except for the shard number:

```yaml
strategy:
  matrix:
    shard: [1, 2, 3, 4]
steps:
  # ... checkout, Ruby, database setup, actions/cache for .saboteur ...
  - run: bundle exec saboteur run --all --shard ${{ matrix.shard }}/4
  - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
    with:
      name: saboteur-report-shard-${{ matrix.shard }}
      path: .saboteur/report.json
```

The upload artifact name cannot contain `/`, so keep the shard number in a
separate matrix value instead of interpolating `1/4` into the name.

Every leg still pays the unchanged-suite baseline and coverage-map cost for
its selected scope. `--shard` splits the mutation work; it does not make
booting the target or building coverage free.

## Reading a shard report

The terminal prints the shard before the report files are named:

```text
Shard 1/4: 73 of 291 planned mutants; inventory sha256:<digest>; partial run
```

The planned count and inventory digest should match across every shard that
used the same commit, scope, config and seed. A different digest means the
legs did not plan the same inventory, so their reports do not combine into
one whole-project result.

Each shard report is marked partial. The Stryker JSON carries a `shard`
object with the index, total, selected count, planned count, inventory
digest and `partial: true`. The agent JSON reports `status: "partial"` with
an incomplete reason of `shard`, whose count is the number of planned mutants
assigned to other shards. saboteur does not merge shard reports into one
combined score; use the reports as evidence that each named shard passed.
