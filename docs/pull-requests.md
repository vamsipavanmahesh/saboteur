# Mutation testing on pull requests

Use diff mode as the default pull-request workflow:

```sh
git fetch origin main
bundle exec saboteur run --since origin/main
```

Replace `main` with the pull request's target branch. The ref must exist
locally, and git must have enough history to find its merge base with HEAD.
An unknown ref or missing merge base fails the run; it does not silently
fall back to a whole-project run. Plain `saboteur run` still means the whole
configured project. Neither the CLI default nor the public API changes.

## GitHub Actions

This example runs only on pull requests. Adapt the Ruby version, boot files,
database setup and SimpleCov guard to your project before using it.

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
          fetch-depth: 0
      - uses: ruby/setup-ruby@14594264cd68ce8a2345dd349bc3d138a4ef85c8 # v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - name: Mutate changed code
        env:
          BASE_REF: ${{ github.base_ref }}
        run: bundle exec saboteur run --since "origin/$BASE_REF"
```

Full checkout history includes the base branch. Pass the base branch through
an environment variable rather than inserting its name directly in shell code.
This repository's [CI workflow](../.github/workflows/ci.yml) already follows
this pattern with `bundle exec exe/saboteur` for the local executable.
Do not run untrusted pull-request code with secrets or privileged credentials.

## Configuration

Keep shared `.saboteur.yml` settings such as `include`, `exclude`, `require`
and `rspec_args`. Pass `--since` only in the PR job, so a main-branch audit
can use the same config without a diff filter. CLI flags override YAML.

For a dedicated PR-only config, this is also supported:

```yaml
# .saboteur-pr.yml
include: [lib/**/*.rb]
since: origin/main
```

```sh
bundle exec saboteur run --config .saboteur-pr.yml
```

`since` is `null` by default. For whole-project audits, omit `since` or set
`since: null` in the chosen config. Omitting the CLI flag does not clear a
`since` value stored in YAML. There is no `--no-since` flag.

## What gets checked

saboteur compares the working tree to the merge base of the ref and HEAD,
including tracked uncommitted changes. It selects methods whose current
source lines intersect the diff. Within each selected method, it keeps fine
mutants whose edits touch changed lines, plus the available coarse whole-method mutants
(`nil`, or `true`/`false` for predicates, and `raise` where applicable). Keep new files tracked so git diff can see them.

Diff mode still builds a per-test coverage map from the configured suite
when there is no valid cached map. A smaller mutation scope does not remove
that fixed cost. `--incremental` is a separate opt-in verdict cache, not a
requirement for diff mode.

This is not impact analysis: unchanged callers of changed dependencies,
methods outside `include`, and deleted methods are not all rechecked.
Run a whole-project audit on main without `since` or `--incremental`, and
periodically while reviewing cross-cutting changes. A no-change PR can have
zero mutants; that is not a whole-project test-quality claim.

## Measured branch history

[The paired measurement](../bench/since/README.md) uses saboteur's real
`--seed` change and records cold-cache full/diff runs, commands, per-mutant
verdict parity and limitations. It is a small self-hosted source workload,
not evidence that a mid-size Rails pull request meets Milestone 1's exit bar.
