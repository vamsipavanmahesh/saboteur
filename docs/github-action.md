# GitHub Action

saboteur ships a ready-made GitHub Action. On a pull request it runs diff
mode against the exact base commit recorded in that pull request event. The
action uses the real merge base between that commit and the PR checkout, so a
later move of the target branch cannot widen or shift the mutation scope. It is
advisory by default: survivors show up as a warning and in the job summary, and
the check stays green.

## Use it

Add saboteur to your Gemfile, then add this workflow. It follows the security
guidance in [the pull-request guide](pull-requests.md): read-only token and no
secrets. It starts with the normal shallow PR checkout and fetches additional
PR history only as needed to prove a merge base.

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

Pin the action to a release tag or a full commit SHA once a release that
contains it is published. `@main` follows development.

The action does not set up Ruby or install gems. Your project's own setup
(Ruby version, database, boot files) stays in your workflow, where you can see
it. The action reads the base SHA from `github.event.pull_request.base.sha`;
there is no user-settable base branch or SHA. It verifies `HEAD` matches
`github.sha`, fetches that exact base commit if needed, then deepens only the
PR merge ref in bounded increments (up to 2,000 commits) until Git can prove a
merge base. If it cannot, the action stops before starting saboteur and prints
instructions. It never substitutes a moving branch tip or widens the scan.
The PR job remains `pull_request`, not `pull_request_target`.


## What lands on the pull request

Each surviving mutant becomes a file/line annotation on the diff: the subject,
the operator, the original text and what saboteur replaced it with. The job
summary lists the same survivors, coarse mutants first (a surviving coarse
mutant hints that no test pins the method's behavior), then file, line and
digest. The JSON report is uploaded as the run's `saboteur-report-<job>-<matrix
leg>` artifact on every pull request run that produced a trusted report -
including an enforced survivor failure - and the summary links it. An early
failure before saboteur runs keeps no report, so a stale one is never
published.

Both read the report's `saboteur.findings` section, written by saboteur 0.3.0
and later, which bounds the list (10, GitHub's own per-step annotation limit)
and counts what it left out. With an older saboteur the action still reports
the counts, the score and a warning, but there are no per-survivor notes.
Accepted survivors (on `config/saboteur_ignore.rb`) get no note; they are counted
in the `accepted-survivors` output and the summary's score line, and the
summary lists them apart with the reason from the ignore list.


## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `command` | `bundle exec saboteur` | How to start saboteur. |
| `arguments` | empty | Extra saboteur arguments, such as `--jobs 2`. Split on whitespace; shell quoting is not supported, so a value with a space cannot be passed. `--since` and `--json` belong to the action and are rejected here, including shortened forms like `--js`, and a bare `--` is rejected. |
| `fail-on-survivors` | `false` | `true` or `false`; any other value fails the step. `true` fails the step when a mutant survives, and also when the run is incomplete (see below). |
| `max-timeouts` | empty | Passed as `--max-timeouts`: a count (`3`) or a percentage of the executed mutants (`5%`, at most 100). saboteur exits 1 when more mutants end as a timeout. Anything else fails the step with exit 2. Empty sets no gate. |
| `max-errors` | empty | Passed as `--max-errors`, same shape. With a value set, errored mutants within the limit no longer fail an incomplete run under `fail-on-survivors: "true"`. |
| `max-duration` | empty | Passed as `--max-duration` (for example `10m`): a wall-time budget for the whole run. On a stop saboteur exits 4, the step fails and the summary says the budget ran out. Empty sets no budget - a big diff then runs until the GitHub job timeout kills it with no summary, so set one. |
| `cache` | `true` | `true` or `false`; any other value fails the step. `false` skips restoring the cached coverage map and also passes `--no-cache` to saboteur, so the map is rebuilt. |
| `report-path` | `.saboteur/report.json` | Where the JSON report is written. Letters, digits, `.`, `_`, `/` and `-` only, and it may not start with `-`. |
| `artifact-name` | `saboteur-report-<job>-<matrix leg>` | Name of the uploaded JSON report artifact. Set it when one job uses this action more than once: upload-artifact rejects a second upload under one name. |
| `review-comments` | `false` | `true` posts surviving mutants as review comments on the pull request's changed lines. Anything but `true` posts nothing. Needs `pull-requests: write`; see "Review comments" below. |
| `max-comments` | `10` | The most review comments kept on the pull request. Survivors beyond it are counted in one summary comment that links the run. |
| `github-token` | `${{ github.token }}` | Token the comments are posted with. |
| `bot-login` | `github-actions[bot]` | Login of the account `github-token` posts as. Only its comments are deduplicated and removed. Set it when the token is a personal access token or an app token, or the cap is posted again on every push. |
| `baseline` | empty | Path of an accepted survivor baseline. Runs `saboteur baseline check` instead of the diff-mode run; see "Failing on new survivors with a baseline" below. |
| `baseline-epsilon` | empty | Only with `baseline`. The largest allowed score drop in percentage points (0 to 100, at most three decimals). |

The action runs only on `pull_request` events. On any other event, such as
`push`, it prints a notice and does nothing. It does not support
`pull_request_target`, which would run with privileges.

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
- A failed gate (`max-timeouts`, `max-errors` or a `--threshold` in `arguments`), which is saboteur exit 1, only with `fail-on-survivors: "true"`.
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
`config/saboteur_ignore.rb` still count as survived in the score, and are reported
in `accepted-survivors`, not `survivors`. The score is `n/a` when no mutant was
scored. That can mean the pull request changed no covered methods, or that
every mutant errored or had no coverage. Read `errors` and the summary to tell
which.

A pull request is also limited by what diff mode selects, and by the
`max_mutants_per_method` cap. The score says nothing about the whole project.

## Review comments

Set `review-comments: "true"` to post each surviving mutant as a review comment
on its changed line, next to the annotation. The comment shows the operator,
the original text, the mutant and a short hint, and starts with a hidden marker
holding the mutant's digest. Nothing is posted by default.

The job needs `pull-requests: write` on top of the usual `contents: read`:

```yaml
permissions:
  contents: read
  pull-requests: write
```

and the action step gets the input:

```yaml
      - uses: vamsipavanmahesh/saboteur@main
        with:
          review-comments: "true"
```

How it behaves:

- At most `max-comments` comments are kept. When more survivors exist, one
  summary comment says how many were left out and links the run and its report.
- A survivor already commented is not posted again on the next push. Survivors
  saboteur labels `likely_equivalent` or `arid`, and accepted survivors, get no
  comment.
- A comment is removed, and a stale summary comment too, only when the report
  says `saboteur.complete` is true: the run judged everything it selected. A
  run that errored, hit a resource limit, was stopped early or sharded, skipped
  files, or had mutants left unverified removes nothing, because a survivor may
  simply not have been looked at. Posting goes on either way.
- Only comments written by `bot-login` are ever touched. Mutation text comes from
  the pull request's code, so it is shown in a code block and stripped of
  control and direction-changing characters.
- It comments only on `pull_request` runs from the same repository. A fork's
  token is read-only, so the step prints a notice and does nothing. The step
  never fails the job: a refused or failed GitHub call becomes a warning.
- A comment sits on the first changed line of the mutated code, moved back to
  the pull request's head commit when the base branch changed the file after the
  pull request branched. A mutant whose line cannot be placed with certainty gets
  no comment and is counted in the "more surviving mutants" summary.

## Failing on new survivors with a baseline

Accept today's survivors once with `saboteur baseline propose` and
`saboteur baseline accept` (see the README), commit the baseline file, then set
two inputs:

```yaml
- uses: vamsipavanmahesh/saboteur@main
  with:
    baseline: config/saboteur-baseline.json
    baseline-epsilon: "2"
    fail-on-survivors: "true"
```

With `baseline` set, the action runs `saboteur baseline check` on the whole
project instead of the diff-mode run, so the `score`, `killed`, `survivors` and
report outputs stay empty and no annotations are written. The check fails on new,
changed or unmatched survivors. `baseline-epsilon` (0 to 100, percentage points)
adds a second failure: the fresh score is more than that far below the score
recorded in the baseline. A score that rose never fails. The drop is compared with the limit exactly (as fractions, not floats), so a drop of exactly the limit passes. The step reads the result strictly: an unknown state, a state that disagrees with the exit status, malformed categories, a missing exit code, non-empty issues, or (with an epsilon) a missing, non-finite or self-contradicting score fails the step with exit 3 instead of passing. With an epsilon the step recomputes the verdict from the result's detected and scored counts with integer arithmetic, and the result's epsilon must equal the input. `baseline-epsilon` takes at most three decimals. Without
`fail-on-survivors: "true"` a review-needed result is a warning and the step stays
green, as in diff mode; an invalid, incompatible or incomplete check always fails
the step. Outputs: `baseline-state` (`clean`, `review_required`, `incompatible`
or `incomplete`) and `baseline-score-drop`. Do not pass `--baseline`, `--epsilon`,
`--proposal` or `--previous` in `arguments`; the action sets them. Unlike the
diff-mode run, the baseline check runs on any event except `pull_request_target`,
which it refuses.

A whole-project check runs every mutant, so it costs far more than a pull request
run. Use it on a schedule or on pushes to your main branch rather than on every pull
request, and keep the diff-mode run for pull requests.

## Going from advisory to enforced

1. Run in advisory mode for a while and read the job summaries.
2. Add `config/saboteur_ignore.rb` entries (each with a reason) for survivors you
   accept.
3. Set `fail-on-survivors: "true"`. saboteur's own CI does this.

## Per-path gates

One subtree can be held to a stricter floor than the rest of the run. In
`config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.score_gate "app/payments/**/*", min_score: 95
end
```

The gate scores only the mutants under its pattern and fails the step under
its floor, with the matched files and failing subjects named in the log.
The global `--threshold`, if any, stays the fallback for everything else.
See [Best practices](best-practices.md) for when to raise a floor.

## Caching

The action caches the coverage map files (`.saboteur/coverage-*.json`) and
nothing else: not reports, logs or `--incremental` verdicts. The coverage map
name contains a hash of the files it was built from, so changing a listed input
(source files, spec files, `config/saboteur.rb` settings) leads to a rebuild. The
hash cannot see everything: an environment variable, a database fixture or the
Ruby version can change coverage without changing a listed file. If a run
looks wrong, set `cache: "false"`. That skips the restore and passes
`--no-cache`, which makes saboteur rebuild the map. The rebuild runs the specs
saboteur selected for the run once: the inferred specs by default, or the whole
suite when the run passes `--all`.

The cache key uses the runner OS, `Gemfile.lock`, `config/saboteur.rb`,
`config/saboteur_custom_map.rb` and `config/saboteur_ignore.rb`, plus the commit. A run restores the newest earlier entry with the same prefix. If you
change `cache_dir` in `config/saboteur.rb`, the action does not cache your new
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
- **The baseline gate is a whole-project check, not a diff-mode run.** See
  "Failing on new survivors with a baseline" above.

## Packaging

The action lives in this repository as a composite action (`action.yml` at the
root, logic in `action/run-saboteur`). That keeps the action and the saboteur
version it expects in one commit and one review. If the Action ever needs its
own release cadence or a Marketplace listing, it can move to its own
repository without changing the inputs above.

The logic is tested by `spec/action/pull_request_run_spec.rb`, which runs the
script against a stand-in saboteur command, including real shallow-fetch and
merge-base cases, annotation escaping, artifact handling, and malformed
reports. The repository's dogfood workflow uses the action on its own pull
requests.
