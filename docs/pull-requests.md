# Mutation testing on pull requests

Use diff mode as the default pull-request workflow:

```sh
git fetch origin main
bundle exec saboteur run --since origin/main
```

Replace `main` with the pull request's target branch. The ref must exist
locally, and git must have enough history to find its merge base with HEAD.
An unknown ref exits 2 (a usage error) before the target boots, and a
missing merge base exits 3; neither silently falls back to a whole-project
run. A method whose only changes are comments, blank lines or spacing is
skipped, and the run says so: its syntax tree is the same as at the merge
base, so a mutant of it would test nothing the change touched. `__LINE__`
counts as its line number, so a method that uses it and moves, or has a line
added above that use, still runs. Inside a method that did change, a line
whose only change is layout is not a changed line either (#313): wrapping
existing statements in a block re-indents them, and only the new block lines
and real edits get line-level mutants. The filter only narrows mutants:
subject selection still reads every touched line, so a method that was only
re-indented is found and reported as formatting-only. A line counts as
layout-only when `git diff -b` pairs it with a base line and Prism reads both
as the same tokens, so whitespace inside a string, heredoc or regexp still
counts as a change. The method's whole-body mutants still run. Plain `saboteur run` still mutates the whole
configured project, but since 0.7.0 it infers the specs named after the
mutated files and runs only those. A mutated file with no conventional spec
borrows the specs that read the constants it defines (at most 10; the run
says it chose them by constant reference, not by name). With none, too many,
or a same-named spec elsewhere, the run stops (exit 2) with the ways out. A `--since` run keeps that stop
only when a score gate (`--threshold` or a mutant-count gate) is set or no
changed file maps to a spec: a gate judges the score, and a partial mapping
would narrow what it covers. Without a gate, each unmapped changed file gets
a loud warning and the run mutates the mapped subset; lines nothing else
covers surface as NoCoverage (#370). Pass `--all` (config
`c.test_selection = :all`) to keep the whole configured suite.

## GitHub Actions

For a ready-made step, use [the saboteur GitHub Action](github-action.md). The
example below shows the same thing written out by hand.

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
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: bundle exec saboteur run --since "$BASE_SHA"
```

The base commit SHA comes from the pull-request event, not a moving branch tip.
Pass it through an environment variable rather than inserting it into shell
code. This manual example fetches full history so Git can establish a real merge
base. If a merge base is unavailable, the command fails rather than widening
the scan. The ready-made action can start shallow and deepens only the PR merge
ref as needed.
For the ready-made action, checkout must match the event's `github.sha`; the
action checks this before using history. This repository's dogfood CI calls the
local action with `uses: ./` and is not an example of the manual `BASE_SHA`
workflow above.
Do not run untrusted pull-request code with secrets or privileged credentials.

## Configuration

Keep shared `config/saboteur.rb` settings such as `include`, `exclude`, `require`
and `rspec_args`. Pass `--since` only in the PR job, so a main-branch audit
can use the same config without a diff filter. CLI flags override `config/saboteur.rb`.

For a dedicated PR-only config, `since` can be set to the exact 40-character
base commit SHA from the event payload. Do not put a moving branch name in a
PR config; refresh the SHA for each event, or pass it as a CLI argument as in
the workflow example above.

`since` is `nil` by default. For whole-project audits, omit `since` or set
`c.since = nil` in the chosen config. Omitting the CLI flag does not clear a
`c.since` value stored in `config/saboteur.rb`. There is no `--no-since` flag.

## What gets checked

saboteur compares the working tree to the merge base of the supplied ref and
HEAD, including tracked uncommitted changes. For pull requests, use the exact
base SHA from the event payload rather than a branch name; the SHA pins the
comparison input, while the merge base still defines the branch point. It
selects methods whose current source lines intersect the diff. Within each
selected method, it keeps fine mutants whose edits touch changed lines, plus
the available coarse whole-method mutants (`nil`, or `true`/`false` for
predicates, and `raise` where applicable). Keep new files tracked so git diff
can see them.

The run executes every spec file the diff adds or changes, on top of the
specs inferred for the mutated files: a spec-only PR still exercises its own
specs against any mutants the change selected.

Diff mode still builds a per-test coverage map from the inferred or named
specs when there is no valid cached map. A smaller mutation scope does not
remove that fixed cost. `--incremental` is a separate opt-in verdict cache,
not a requirement for diff mode.

This is not impact analysis: unchanged callers of changed dependencies,
methods outside `include`, and deleted methods are not all rechecked.
Run a whole-project audit on main with `--all` and without `since` or
`--incremental`, and periodically while reviewing cross-cutting changes. A no-change PR can have
zero mutants; that is not a whole-project test-quality claim.

## Measured branch history

[The paired measurement](../bench/since/README.md) uses saboteur's real
`--seed` change and records cold-cache full/diff runs, commands, per-mutant
verdict parity and limitations. It is a small self-hosted source workload,
not evidence that a mid-size Rails pull request meets Milestone 1's exit bar.
