# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- [docs/scores.md](docs/scores.md) defines the covered score, the overall score a
  Stryker dashboard shows, assertion and crash kills, and what makes a run
  incomplete (#198).
- A startup warning on stderr when the working tree has uncommitted changes,
  because mutants run your code and could alter or delete files. Saboteur's own
  output paths do not count as changes.
- `endpoint_replacement` swaps explicit no-argument `first` and `last` calls,
  including safe navigation. Calls with arguments or blocks, bare calls,
  arid statements and nested scopes are excluded.
### Fixed
- **Safety:** mutants that would leave a directly-written destructive call
  running with altered inputs are suppressed (#102). A syntactic hazard
  guard matches calls written directly - `FileUtils.rm*`/`remove_entry*`
  (bare names included), `File.delete`/`unlink`, `Dir.rmdir`/`delete`/
  `unlink`, `rmtree`, `system`/`exec`/`spawn` (bare or on `Kernel`/
  `Process`), backticks/`%x`, `IO.popen`, `Open3.*`, piped `open` - and
  suppresses mutants inside such a call or elsewhere in a method that still
  holds one. Calls behind aliases, variables or `send` are not recognized.
  A canary re-checks the tracked tree after each method's mutants and aborts
  with exit 3 when a file vanishes: detection after the damage, per method,
  with no restoration. Configure the list via `c.hazard`; `--allow-hazardous`
  opts out.
- Endless defs (`def x = ...`) are no longer skipped as "no coverage": the
  coverage map now also records per-test method calls, which is how Ruby
  reports endless-def bodies. A whole-suite build that records neither a line
  hit nor a method call still stops with a clearer cause message. (#107)

## [0.4.0] - 2026-10-12

### Changed
- **Breaking:** configuration moved from YAML to Ruby. `.saboteur.yml` becomes
  `config/saboteur.rb` (`Saboteur.configure do |c| ... end`, same key names),
  and `.saboteur-ignore.yml` becomes `config/saboteur_ignore.rb`
  (`Saboteur.ignore do |i| i.mutation "<digest>", subject:, reason: end`,
  reason still mandatory). A legacy YAML file stops the run with a pointer to
  the new file instead of being read. Unknown settings fail with the line
  number and a did-you-mean suggestion. `rails generate saboteur:install`
  writes `config/saboteur.rb` (never overwriting without `--force`);
  `config/saboteur_ignore.rb` and `config/saboteur_custom_map.rb` are optional
  and created by hand when needed.
- A run in which more than half of the executed mutants errored now exits 3
  (the tool failed). Before, only a run where every executed mutant errored
  did. Errored mutants are outside the score, so such a run tested almost
  nothing. This applies with and without `--threshold`. The JSON report records the reason under
  `saboteur.exitCause` (`ok`, `survivors`, `belowThreshold`, `errorMajority`,
  `incompleteUnderThreshold`; in `--agent` mode `ok`, `survivors`,
  `errorMajority` or `incomplete`).
- A whole-suite coverage build that records no lines for any included file
  now exits 3 and the empty map is not cached, instead of testing nothing.
  With `--test`, an empty map stays a legitimate "no coverage" outcome.
- Rails fixtures (`spec/fixtures`, `test/fixtures`), `db/structure.sql`,
  `db/schema.rb` and `config/*.yml` are part of the coverage and verdict
  cache fingerprint, so a changed fixture or schema invalidates cached
  results. The new `fingerprint_extra` setting adds other globs whose
  contents should invalidate caches, for example `data/*.csv`.
- The baseline and coverage phases show progress and write real logs, so a
  slow or failing phase can be diagnosed from the output.
- When the baseline child is killed by a signal, the message names it
  (`SIGKILL` adds a possible-OOM hint) instead of reporting a bare failure.

### Removed
- The coarse-survivor gate: a surviving whole-body mutant no longer skips the
  method's fine mutants; every eligible fine mutant runs.

### Fixed
- Mutations inside private `module_function` helpers are preserved when the
  method is re-evaluated; they previously reverted and reported as false
  survivors.
- Rails apps that test against in-memory SQLite (`:memory:`) no longer fail
  in forked workers with "Could not find table": saboteur never disconnects,
  renames or copies an in-memory pool. Each in-memory database is
  snapshotted to a temporary file after boot, and every forked child
  restores the snapshot into its own fresh database.
- With a Rails app under Bootsnap, Coverage no longer sees an empty map:
  saboteur sets `DISABLE_BOOTSNAP_COMPILE_CACHE=1` for its own process when
  the variable is unset, because bytecode from Bootsnap's compile cache
  carries no coverage counters.
- A relative SQLite `database:` path resolves against `Rails.root` (as Rails
  7.1+ does) for the per-worker copy and its cleanup. The copy uses SQLite's
  backup API after a WAL checkpoint, refuses to run when a reader keeps the
  WAL busy, and a missing source file is an error rather than a skipped copy.
- Per-worker database copies (`jobs` above 1) are dropped when the run ends,
  best effort: a failed drop is a warning and never changes the outcome. A
  copy left by a killed run is reclaimed by the next run. A failed copy
  names the sessions blocking it.
- For `rails: true`, the app's `spec/` directory is on the load path before
  `require` is processed, as with rspec, so a boot file such as a dummy app's
  `spec/rails_helper.rb` can require its siblings.
- When Rails did not load, the error points engine users at the dummy app's
  environment file or helper (`DummyApp.setup` in `spec/rails_helper.rb`).

### Added
- `rails generate saboteur:install` and a Rails quickstart in the README. The
  generator writes `config/saboteur.rb` and never overwrites without `--force`.
- The warning about threads alive when a worker forks names those threads,
  falling back to their backtraces for unnamed ones.
- `--test` no longer requires source operands when `--since` is given: the
  changed files are the sources, so `saboteur run --since origin/main --test
  spec/billing_spec.rb` scopes a pull-request run to chosen specs. A `--since`
  run without `--test` now warns before it starts that the two baseline passes
  run the loaded suite (a cold coverage cache adds one more pass), with the
  spec-file count and how to scope them, instead of going quiet for hours on a
  large app.
- `config/saboteur_custom_map.rb` declares explicit source-file to spec-file
  mappings (`SABOTEUR_CUSTOM_MAP`): exact paths, globs (the more specific glob
  wins; equal specificity is an error) and Regexps with capture substitution.
  Invalid maps fail the run with the file and key; stale and duplicate keys
  warn on runs, and `saboteur doctor` fails on stale keys. The map is parsed
  and validated only for now - it does not change which specs run yet.

- An integration target can declare a known error profile
  (`allow_error_fraction` per strategy in integration/targets.yml): the
  majority-error exit is accepted only when the run's own fresh report
  carries the CLI's `errorMajority` marker, the errored fraction stays
  within the bound, and no mutant hit a resource limit. The JSON report
  records the run's exit cause under `saboteur.exitCause`.
- A survivor lists the first five tests that covered its line and still passed
  with the mutant applied, in the terminal and the HTML page.
- In diff mode (`--since`), each survivor names the changed line it relates to
  (`changed line: path:N` in the terminal, `changedLines` in each JSON finding),
  because a multi-line statement is reported at its first line.
- The score is split into assertion kills and crash kills, in the terminal,
  the JSON report (`saboteur.scores`) and the HTML page. A second score leaves
  out whole-body mutants (`body_nil`, `body_true`, `body_false`, `body_raise`). The headline score and
  `--threshold` are unchanged.
- `saboteur run --agent` (`--format agent`): one bounded JSON summary (under 8 KiB) on stdout
  with status, verdict, provenance, the first three findings and the commands for full
  detail. Exit 0 means a complete, clean run only: 1 survivors, 2 usage or config error,
  3 incomplete or failed. `--threshold` cannot be combined with it. The next commands are shell-escaped and keep the
  full selection; the working-tree state is read before the run; target output stays on stderr. `saboteur agent-skill`
  prints an AGENTS.md block for coding agents (also in `docs/agent-skill.md`). Classic
  exit codes are unchanged.
- Fine `pair_removal` mutants for hash literals and keyword lists, including
  sole associations, with token-based separators and the normal method cap.
- Fine `argument_removal` mutants: remove one ordinary argument from a
  parenthesized call while preserving keywords and blocks. Token-based comma
  edits respect comments and strings. Existing candidate validation, order and
  per-method caps apply. Unparenthesized calls and heredoc arguments are skipped.

## [0.3.0] - 2026-10-11

### Added
- Fine `literal_boolean` and `literal_string` mutants: true/false swaps and
  nonempty static string replacement with `""`. Body-only traversal excludes
  arid/nested scopes, interpolation, heredocs and non-string text literals.
  New proposals can change scores and per-method-cap coverage.
- `saboteur run --id DIGEST`: replay one exact current mutant with selected tests,
  independent of caps, coarse gating, ignore suppression and incremental reuse.
  Prints the mutation diff and selected test ids for every replay result.
- Review findings in the JSON report (`saboteur.findings`,
  `Saboteur::Reporter::Findings`): a bounded, deterministically ordered list
  of survivors (coarse first, then file, line and digest) with the file,
  line, digest, subject, operator, original and replacement a note on a
  pull-request diff needs. Survivors accepted on the ignore list are listed
  separately with their reason; `survivorsTruncated` counts the rest, which
  stay in the full `files` data.
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
- `saboteur run SOURCE... --test TEST...`: mutate the named source files and
  run only the named spec files or directories. Positional sources replace
  `include` and `exclude`; `--test` replaces the spec paths in `rspec_args`.
- `--threshold PERCENT` (and `threshold:` in `.saboteur.yml`): exit 1 when the
  score is below PERCENT. The score decides the exit code instead of survivors.
  It fails closed: no score exits 1, and errored or resource-limited mutants
  exit 3.
- Positional sources must exist (exit 2 otherwise), and the selected tests are
  part of the coverage-map and `--incremental` cache keys.

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
- Subjects found with Prism; mutations are byte-range edits: whole-body
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
