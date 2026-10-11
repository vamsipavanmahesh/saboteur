# GitHub Action

saboteur ships a ready-made GitHub Action. On a pull request it runs diff
mode (`saboteur run --since origin/<base branch>`), so only the methods the
pull request changed are mutated. It is advisory by default: survivors show up
as a warning and in the job summary, and the check stays green.

## Use it

Add saboteur to your Gemfile, then add this workflow. It follows the security
guidance in [the pull-request guide](pull-requests.md): read-only token, full
history, and no secrets.

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
      - uses: vamsipavanmahesh/saboteur@main
```

Pin the action to a release tag or a full commit SHA once a release that
contains it is published. `@main` follows development.

The action does not set up Ruby or install gems. Your project's own setup
(Ruby version, database, boot files) stays in your workflow, where you can see
it. The action needs `fetch-depth: 0` on checkout; it stops with a message
that says so when the checkout is shallow or the base branch is missing.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `base-ref` | the pull request's base branch | Branch to diff against. Empty outside pull requests, where the action does nothing. |
| `command` | `bundle exec saboteur` | How to start saboteur. |
| `arguments` | empty | Extra arguments, separated by spaces, such as `--jobs 2`. |
| `fail-on-survivors` | `false` | `true` fails the step when a mutant survives. |
| `cache` | `true` | Caches `.saboteur`, which holds the coverage map. |
| `report-path` | `.saboteur/report.json` | Where the JSON report is written. |

A saboteur usage error (exit 2) or tool error (exit 3) always fails the step,
even in advisory mode. A broken setup that reports green would be worse than
a red check.

## Outputs

`ran`, `exit-code`, `score`, `killed`, `survivors` and `report-path`. The score
is a percentage with one decimal, or `n/a` when no mutants were scored. A
pull request that changes no covered methods has nothing to mutate; that says
nothing about the whole project's test quality.

## Going from advisory to enforced

1. Run in advisory mode for a while and read the job summaries.
2. Add `.saboteur-ignore.yml` entries (each with a reason) for survivors you
   accept.
3. Set `fail-on-survivors: "true"`. saboteur's own CI does this.

## Caching

The action caches the `.saboteur` directory. The coverage map in it is keyed by
a hash of the files it was built from, so a stale map is never reused: it is
rebuilt. Building the map runs your whole suite once, which is the fixed cost of
a run. The cache key uses `Gemfile.lock` and `.saboteur.yml`, and the cache
falls back to the newest earlier entry for the same key prefix. Set
`cache: "false"` to turn it off. Verdict reuse (`--incremental`) is not
enabled by default; pass it in `arguments` if you want it.

## What it does not do yet

- **No pull request comment.** Posting a comment needs a token with
  `pull-requests: write`, and pull requests from forks never get one. The
  action keeps to a read-only token and writes a job summary and a workflow
  warning. A comment can be added later as a separate step in a workflow that
  you trust, reading the JSON report. It must not run the pull request's code.
- **No baseline file.** There is no way yet to accept today's survivors and
  fail only on new ones. See the [roadmap](../ROADMAP.md).

## Packaging

The action lives in this repository as a composite action (`action.yml` at the
root, logic in `action/run-saboteur`). That keeps the action and the saboteur
version it expects in one commit and one review. If the Action ever needs its
own release cadence or a Marketplace listing, it can move to its own
repository without changing the inputs above.

The logic is tested by `spec/action/pull_request_run_spec.rb`, which runs the
script against a stand-in saboteur command. This repository's `dogfood` CI
job uses the action (`uses: ./`) on its own pull requests.
