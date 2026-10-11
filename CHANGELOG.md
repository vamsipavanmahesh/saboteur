# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `saboteur run --id DIGEST`: replay one exact current mutant with selected tests,
  independent of caps, coarse gating, ignore suppression and incremental reuse.
  Prints the mutation diff and selected test ids for every replay result.
- Self-contained HTML report (`Saboteur::Reporter::Html`): one file with inline
  style and no script or network use, written to `.saboteur/report.html`.
  Change the path with `--html PATH` or `html_report:`. It shows the score,
  per-file mutants, survivors, warnings and skipped subjects.
- A GitHub Action (`uses: vamsipavanmahesh/saboteur`) that runs diff mode on pull
  requests. Advisory by default, with a job summary, outputs and a cached
  coverage map. See `docs/github-action.md`.
- Built-in `filter_replacement` mutants: `select` / `reject` and
  `select!` / `reject!`, for explicit-receiver calls with a block and no ordinary
  arguments. For unchanged subjects, existing mutants retain their digests and order.
  Runs may now include more mutants and report a different score.
- `saboteur doctor [--config PATH] [--seed N]`: environment checks and two fresh
  unchanged-suite checks, without mutation reports or coverage/verdict cache writes.

## [0.2.0] - 2026-10-10

### Added
- `--seed N` (and `seed:` in `.saboteur.yml`, default 1): every test run seeds
  Ruby's random numbers with it, so runs repeat; the report prints the seed.

### Fixed
- Linux: killed orphans adopted by the supervisor are reaped reliably, so no
  zombies are left behind (first run on Linux CI).
- The README status line describes what has actually been tested.

## [0.1.0] - 2026-10-10

First release that does mutation testing. MIT licensed.

### Added
- `saboteur run` with `--since`, `--subject`, `--timeout-factor`, `--jobs`,
  `--reeval`, `--json`, `--no-cache`, `--incremental`, `--config`.
- Subjects found with Prism; mutations are byte-range edits: whole-method
  `nil`/`true`/`false`/`raise` first, then comparison, boolean, arithmetic,
  numeric literal, statement removal, condition, negation, safe navigation
  and `||=`.
- Per-example test selection from a per-test coverage map, cached by content
  hash; timeouts scaled from each test's recorded duration.
- Verdict check: every kill is re-run on the unchanged method, so a test that
  fails anyway cannot count as a kill.
- Supervised children: whole process tree tracked and killed, deadline,
  memory and process caps, CPU-limit backstop, recursion guard.
- Parallel workers (`--jobs N`), including Rails apps on Postgres and SQLite
  with a database copy per worker.
- RSpec adapter and a Rails profile. Minitest is out of scope.
- Terminal report with unified diffs, Stryker JSON report, ignore list with
  mandatory reasons, incremental result cache.
- Mutation-source extension point and lifecycle hooks.

## [0.0.1] - unreleased

### Added
- Gem skeleton to reserve the name. No mutation testing yet.
