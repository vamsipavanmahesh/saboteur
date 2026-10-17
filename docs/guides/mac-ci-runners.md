# Self-hosted Mac runners and CI sharding

The macOS CI legs run on the owner's self-hosted runner pool, not on
GitHub-hosted runners. This page describes the pool, the fork rules around
it, and the round-robin sharding every test leg uses. Everything here
describes `.github/workflows/ci.yml` and `script/rspec-shard` as they ship
on `main`.

## The `saboteur-mac` pool

`test-macos` runs on `runs-on: [self-hosted, saboteur-mac]`: any registered
self-hosted runner carrying the `saboteur-mac` label. The pool is three
physical runner instances, so the job matrix sets `max-parallel: 3` - more
parallel legs would just queue behind the third machine.

The matrix changes with the event:

- **Pull requests** run the smallest useful matrix: the latest stable Ruby
  only, three shards - three legs, one per instance.
- **Pushes to `main`** run every supported Ruby (`3.3`, `3.4`, `ruby` -
  latest stable) across three shards: nine legs, three at a time.

Job names use stable OS labels (`Ruby <version> / macos / shard <n>`),
never runner labels, so swapping machines in or out of the pool never
renames a check that branch protection and the
[panel gate](../panel-head-gate.md) wait on (#347). The move to the pool
kept the check names unchanged for exactly this reason (#354).

Each leg checks out the PR head or pushed commit, installs Ruby with
`ruby/setup-ruby` (`bundler-cache: true`, so gems cache between runs) and
runs `script/rspec-shard <n> 3`.

## Fork pull requests never touch the pool

Self-hosted runners must never execute code from a fork, so `test-macos`
carries a guard:

```yaml
if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
```

A fork pull request skips the macOS legs entirely; the Linux legs still run
and still cover the change. The repository additionally requires approval
for all external contributors before any fork workflow runs at all.

## Sharding with `script/rspec-shard`

Every test leg (Linux, macOS, the `LANG=C` locale leg) runs one third of
the suite through the same script:

```sh
script/rspec-shard INDEX TOTAL [extra rspec args...]
```

`INDEX` is 1-based. The script takes the sorted list of
`git ls-files 'spec/**/*_spec.rb'` (fixture projects excluded - their specs
are test data, not the suite) and deals files round-robin across `TOTAL`
shards. Every shard therefore mixes fast unit specs with slow end-to-end
specs, and each file lands in exactly one shard, so the three legs together
cover the whole suite with no overlap.

The split is deterministic: the same tree always produces the same shards,
on any machine. The script is kept Bash 3.2 compatible (no
`mapfile`/`readarray`) because macOS ships Bash 3.2 and the pool runners
use the system shell.

To reproduce one CI leg locally:

```sh
script/rspec-shard 2 3
```

Extra arguments after the totals pass straight to RSpec, so
`script/rspec-shard 1 3 --tag focus` works the same way it would on a
runner.

## Adding or replacing a runner instance

Registration is the standard GitHub self-hosted runner setup for a
repository runner; the only saboteur-specific requirements come from the
workflow:

- Register with the `saboteur-mac` label, or the legs never pick the
  machine up.
- Keep the pool size and `max-parallel` in agreement: with three instances,
  `max-parallel: 3`. A fourth instance does nothing until the matrix value
  changes, and a smaller pool just queues legs.
- The environment must support `ruby/setup-ruby` with `bundler-cache` and
  the system-Bash-compatible scripts (see above).
- Do not rename the job `name:` fields when touching the workflow: branch
  protection and the [panel gate](../panel-head-gate.md) reference those
  exact check names.

The Linux legs (`nscloud-ubuntu-24.04-amd64-*`) follow the same sharding
and naming rules; only the runner pool and the fork guard differ.
