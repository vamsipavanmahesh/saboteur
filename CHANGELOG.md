# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Self-contained HTML report (`Saboteur::Reporter::Html`): one file with inline
  style and no script or network use, written to `.saboteur/report.html`.
  Change the path with `--html PATH` or `html_report:`. It shows the score,
  per-file mutants, survivors, warnings and skipped subjects.
- `saboteur run SOURCE... --test TEST...`: mutate the named source files and
  run only the named spec files or directories. Positional sources replace
  `include` and `exclude`; `--test` replaces the spec paths in `rspec_args`.
- `--threshold PERCENT` (and `threshold:` in `.saboteur.yml`): exit 1 when the
  score is below PERCENT. The score decides the exit code instead of survivors.

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
