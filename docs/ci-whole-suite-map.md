# The whole-suite map in CI

`saboteur install` writes two GitHub Actions workflows that keep a
whole-suite coverage map on main and hand it to every pull request:

- `.github/workflows/saboteur-map.yml` runs on every push to main (and on
  demand). It runs your whole test suite, mutates the whole project once,
  and saves the map to the Actions cache.
- `.github/workflows/saboteur-pr.yml` runs on every pull request. It
  restores the newest main map through the saboteur action and mutates only
  what the pull request changed, confirming survivors against specs the diff
  never loaded.

Install never overwrites a workflow file that is already there; it prints
what it wrote and what it skipped, and the next step when it wrote anything.
Re-run it any time - existing files are left as they are.

## How the cache works

Both workflows name the cache with the same scheme the
[action](github-action.md) restores with: a key hashed from `Gemfile.lock`
and your saboteur config files, plus the commit SHA. A pull request looks up
the newest entry with that prefix, so it gets the latest main map even
though its own commit differs. The cache holds three things, all under
`.saboteur/`: the coverage map, the snapshot of the inputs that produced it,
and the pointer that marks it as whole-suite. A map restored without the
pointer is not read as a whole-suite map, so survivors stay unconfirmed
rather than confirmed against the wrong thing.

## Size and runtime cost

The map is JSON: a few megabytes for a typical app (saboteur's own map is
about 5 MB), well inside the 10 GB Actions cache allowance. GitHub evicts
the least recently used entries first; the prefix scheme means a stale entry
is only ever an older map, never a wrong one.

The expensive half is the main job: it runs your whole suite once, then a
full mutation run of the project. On a large app that is minutes to an hour
per push to main. Ways to tune it:

- Build the map on a schedule instead of every push - the workflow file
  ships with a weekly cron line you can uncomment. A slightly stale map only
  means confirmation falls back to the specs the pull request loaded.
- Pass `--max-duration` (the PR workflow already uses the action's 10 minute
  default) to cap the mutation run; survivors past the cap are reported, not
  hidden.
- Keep `push` triggers off draft-heavy branches by limiting `branches`.

The pull request job itself stays in diff mode: it restores the map in
seconds and mutates only the changed files.
