# GitHub Action

saboteur ships a ready-made GitHub Action. On a pull request it runs diff
mode (`saboteur run --since origin/<base branch>`), so only the methods the
pull request changed are mutated. It is advisory by default: survivors show up
as notes on the diff, as a warning and in the job summary, and the check stays
green.

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

## What lands on the pull request

Each surviving mutant becomes a file/line annotation on the diff: the subject,
the operator, the original text and what saboteur replaced it with. The job
summary lists the same survivors, coarse mutants first (a surviving coarse
mutant hints that no test pins the method's behavior), then file, line and
digest. The JSON report is uploaded as the run's `saboteur-report-<job>`
artifact on every pull request run, even a failed one, and the summary links
it.

Both read the report's `saboteur.findings` section, written by saboteur 0.3.0
and later, which bounds the list (10, GitHub's own per-step annotation limit)
and counts what it left out. With an older saboteur the action still reports
the counts, the score and a warning, but there are no per-survivor notes.
Accepted survivors (on `.saboteur-ignore.yml`) get no note; they are counted
in the `accepted-survivors` output and the summary's score line, and the
summary lists them apart with the reason from the ignore list. A matrix
workflow should give each leg a distinct job name, so the per-job artifact
names do not collide.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `base-ref` | the pull request's base branch | Branch to diff against. |
| `command` | `bundle exec saboteur` | How to start saboteur. |
| `arguments` | empty | Extra saboteur arguments, such as `--jobs 2`. Split on whitespace; shell quoting is not supported, so a value with a space cannot be passed. `--since` and `--json` belong to the action and are rejected here, including shortened forms like `--js`, and a bare `--` is rejected. |
| `fail-on-survivors` | `false` | `true` or `false`; any other value fails the step. `true` fails the step when a mutant survives, and also when the run is incomplete (see below). |
| `cache` | `true` | `true` or `false`; any other value fails the step. `false` skips restoring the cached coverage map and also passes `--no-cache` to saboteur, so the map is rebuilt. |
| `report-path` | `.saboteur/report.json` | Where the JSON report is written. Letters, digits, `.`, `_`, `/` and `-` only, and it may not start with `-`. |

The action runs only on `pull_request` events. On any other event, such as
`push`, it prints a notice and does nothing, even if `base-ref` is set. It does
not support `pull_request_target`, which would run with privileges.

## What fails the step

- A saboteur usage error (exit 2) or tool error (exit 3), always, even in
  advisory mode. A broken setup that reports green would be worse than a red
  check.
- A run where saboteur exits 0 or 1 but this run's report is missing, is not
  exactly one JSON document, is not a schemaVersion 2 report with a `files`
  object, or holds a file entry without a `mutants` list or a mutant with a
  status the action does not know. The action deletes any old report before
  the run, and fails if it cannot, so a report restored from a cache is never
  mistaken for this run's result. The step fails with exit code 3. A report
  with no files is valid: it means nothing was mutated.
- Survivors, only with `fail-on-survivors: "true"`.
- An incomplete run, only with `fail-on-survivors: "true"`. A run is
  incomplete when some mutants errored or hit a resource limit. Those mutants
  are not scored. In advisory mode the step stays green and the summary and
  the `incomplete` output say so.

## Outputs

`ran`, `exit-code`, `report-valid`, `score`, `killed`, `timeouts`, `survivors`,
`accepted-survivors`, `errors`, `incomplete` and `report-path`.

`score` is the covered score, as a percentage with one decimal:
(killed + timeout) / (killed + timeout + survived), over mutants that ran. It
is saboteur's own score. Mutants with no coverage, ignored mutants, errors and
resource limits are not in it. Survivors accepted through
`.saboteur-ignore.yml` still count as survived in the score, and are reported
in `accepted-survivors`, not `survivors`. The score is `n/a` when no mutant was
scored. That can mean the pull request changed no covered methods, or that
every mutant errored or had no coverage. Read `errors` and the summary to tell
which.

A pull request is also limited by what diff mode selects, and by the
`max_mutants_per_method` cap. The score says nothing about the whole project.

## Going from advisory to enforced

1. Run in advisory mode for a while and read the job summaries.
2. Add `.saboteur-ignore.yml` entries (each with a reason) for survivors you
   accept.
3. Set `fail-on-survivors: "true"`. saboteur's own CI does this.

## Caching

The action caches the coverage map files (`.saboteur/coverage-*.json`) and
nothing else: not reports, logs or `--incremental` verdicts. The coverage map
name contains a hash of the files it was built from, so changing a listed input
(source files, spec files, `.saboteur.yml` settings) leads to a rebuild. The
hash cannot see everything: an environment variable, a database fixture or the
Ruby version can change coverage without changing a listed file. If a run
looks wrong, set `cache: "false"`. That skips the restore and passes
`--no-cache`, which makes saboteur rebuild the map. Building the map runs your
whole suite once, which is the fixed cost of a run.

The cache key uses the runner OS, `Gemfile.lock` and `.saboteur.yml`, plus the
commit. A run restores the newest earlier entry with the same prefix. If you
change `cache_dir` in `.saboteur.yml`, the action does not cache your new
directory. Verdict reuse (`--incremental`) is not on by default and is not
cached.

## What it does not do yet

- **No pull request comment.** Posting a comment needs a token with
  `pull-requests: write`, and pull requests from forks never get one. The
  action keeps to a read-only token and writes a job summary and a workflow
  warning. A comment can be added later as a separate step in a workflow that
  you trust, reading the JSON report. It must not run the pull request's code.
- **No installation check in another repository yet.** The dogfood job runs
  the action on this repository only. Treat `@main` as a preview until a
  release has been tried on an outside project.
- **No baseline file.** There is no way yet to accept today's survivors and
  fail only on new ones. See the [roadmap](../ROADMAP.md).

## Packaging

The action lives in this repository as a composite action (`action.yml` at the
root, logic in `action/run-saboteur`). That keeps the action and the saboteur
version it expects in one commit and one review. If the Action ever needs its
own release cadence or a Marketplace listing, it can move to its own
repository without changing the inputs above.

The logic is tested by `spec/action/pull_request_run_spec.rb`, which runs the
script against a stand-in saboteur command, including missing, stale and
malformed reports. This repository's `dogfood` CI
job uses the action (`uses: ./`) on its own pull requests.
