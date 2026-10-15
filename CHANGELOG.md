# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Usability fixes from 0.5.0 field feedback: an unscoped whole-suite run
  announces the example count and the real number of full passes before
  the first one (a cached map counts as reused only when it loads clean)
  and estimates the remaining baseline and coverage time once the first
  baseline pass is timed; past 1,000 examples it also names `--test` as
  the way to scope (#260). The Next steps footer prints the complete,
  shell-safe replay command carrying the run's own selection options
  and the CLI-only switches that change candidate availability or boot,
  in full however long it gets, instead of asking you to reassemble
  them (#261). `--verbose` prints one line per finished subject with its
  result marks, so a survivor is attributable to a method before the run
  ends (#262). The threads-alive-at-fork warning says why the two known
  threads are expected harmless, and under which conditions, and what an
  unknown thread can break (#263). A `chain_removal` survivor's hint
  appends a conditional equivalence note: if the shorter chain proves
  equivalent across the intended inputs, simplify or ignore (#264).

### Fixed
- macOS CI flakes: the supervisor `on_tick` cleanup spec waits for a fully
  written pid before triggering instead of racing the file's first bytes
  (#277), fixture repositories disable Git background auto-maintenance so
  teardown no longer races its lock deletion (#271), and a baseline child
  that exits without a result now has its exit status or signal in the
  error and its dying exception on stderr, so the next flake names its
  cause (#255). The same error carries a bounded tail of the child's
  redirected log, the dying-child warning names its stage ("baseline
  child died during setup/run", "coverage child died during the map
  build"), and a broken child stderr can no longer swallow the exit
  (#289).
- `Saboteur::Engine#call` restores the host process's Coverage state when
  it returns or raises: an embedded engine (a spec, the dogfood's own
  coverage-map build) no longer leaves Coverage suspended for everything
  the host runs afterwards, and a resume that fails because the host
  disturbed Coverage mid-run warns instead of masking the run outcome,
  with worker cleanup running either way (#254). A scoped run (`--since`) no longer
  calls an ignore entry stale when its mutation exists but sits on an
  unchanged line and was scoped out; staleness is judged against each
  examined subject's full, pre-scope candidate digests (#284). A worker
  start-failure storm while the pool is already draining no longer raises
  "workers keep failing to start" over the tool errors that carry the
  real abort cause (#286).
- The canary no longer blames a method's last mutant for deleted files:
  a cheap per-mutant probe (snapshot stats only, about 1.3 ms for this
  repo's 692 watched files against a full inventory's 5 ms) runs after
  every mutant, so the abort names the mutant whose run just ended when
  the loss was detected as the likely cause - with the per-method check
  as the backstop for losses outside a mutant's window (#235).
- Parallel runs aborted by a wiped log dir now name the culprit: a
  worker that only noticed the damage could report "an unknown mutant"
  before the worker whose mutant did it, and the first report won the
  abort. Tool-error reports now carry whether they name a mutant, the
  pool stops handing out new work but lets in-flight workers finish
  and report, and the abort ranks the reports by attribution quality:
  a report that names its mutant first, then a canary trip, then the
  earliest bare report. A canary trip from the end-of-subject check
  folds into the same choice instead of overriding collected reports,
  and the in-flight drain is bounded (a 30-second default drain
  window, followed by worker cleanup), so a wedged worker cannot
  stall the abort (#235).
- `saboteur doctor` prints the coverage line once instead of twice (it is
  still verified before and after target boot), and reports the sandbox
  status: the Landlock ABI when the kernel can deliver it, the gap when
  it cannot, or off when `c.sandbox = false` (#236). The sandbox policy
  no longer creates the project's `tmp/` directory to grant it: the
  grant applies when `tmp/` already exists and only `c.sandbox_writable`
  entries are created (#236).
- The mutant sandbox no longer grants the cache dir: a mutant child
  cannot delete the baseline, the reports or other children's logs,
  and its own log is opened before the fork and inherited as a
  descriptor, with stdio kept explicitly through the sandbox sweep.
  A child log that cannot be opened, or that vanishes mid-run with
  the sandbox off or degraded, aborts the run with exit 3 - the
  canary's hazard report names the culprit when tracked files
  vanished too, otherwise the tool error does - never a mutant
  verdict such as "killing test also fails with the method
  unchanged"; in parallel runs the error aborts the whole run
  instead of degrading into per-mutant errors. The grants are
  additive, so a cache dir placed inside
  `tmp/`, the system temp dir or a `c.sandbox_writable` entry stays
  writable. Note the sandbox prevents the damage, not the verdict:
  with `--allow-hazardous`, a destructive mutant whose test swallows
  the denial (EACCES) can still read as a survivor; by default the
  hazard guard suppresses such mutants and reports the hazard (#234).
- An extensionless `hooks` path now boots: it resolves its `.rb` at load
  time, the way `require` does and matching what doctor accepts (#267).

### Changed
- Breaking: inferred test selection is now the default. Without `--test`,
  a run picks the spec named after each mutated file and runs only those
  for the baseline passes, the coverage pass and every mutant, as `--test`
  would; with `--since` only the changed files count. A file that needs a
  spec and has none now stops the run before it boots (exit 2) and names
  both ways out, instead of silently running the whole suite. Use `--all`
  or `c.test_selection = :all` to keep the old whole-suite behavior.
  `--guess-tests` is a deprecated alias for the default and
  `--no-guess-tests` warns and is ignored; both flags disappear in a
  future release (#270). A `--subject` run infers only from the named
  subjects' files, so an unrelated spec-less file no longer stops a
  one-method run. The unmatched-file guidance names the expected specs
  and tells you to re-run the same command with `--test` followed by your
  existing spec paths, or to append `--all`, instead of printing a
  reconstructed command. `--test` may stand alone (the configured include
  names the sources), so agent rerun/replay commands stay executable; a
  whole-suite `--all` run is recorded in the agent provenance only when
  no tests resolved, so a configured `:all` combined with named tests
  still produces runnable follow-up commands. Baseline evidence is
  fingerprinted from the declared config before inference narrows the
  test list, so `baseline propose` and `baseline check` agree again
  (#275). Two stale ignore-list entries for
  `Saboteur::CLI#define_execution_options` are gone: full runs no longer
  generate those description-string mutants, so the entries could never
  match again.
  A `--subject` run combined with `--since` now infers specs only for
  named subjects inside the diff scope: an unchanged subject file, one
  whose changes sit in other methods, or one with a comment-only change
  no longer stops the run before boot. Agent provenance records tests
  defined in the config file, so rerun and replay commands keep their
  scope instead of falling back to inference.

### Fixed
- Fixed two encoding failures in mutant children running under a non-UTF-8
  locale such as `LANG=C` (seen on CI, where the Landlock sandbox engages):
  the inherited-fd sweep compared a locale-tagged descriptor target against
  grant patterns with string semantics, raising
  `Encoding::CompatibilityError` before any test ran when an open file's
  path carried non-ASCII bytes; and an exception message embedding such a
  path made failure reporting raise the same way, turning a killed mutant
  into an errored run. The sweep now compares raw bytes, and failure
  messages are scrubbed before their first line is extracted; if the
  scrub itself raises - it is mutable code, and the mutant under test
  may have broken it - an escaped fallback keeps the failure a clean
  kill instead of an errored run (#272).
- Fixed `--guess-tests` falling back to the whole suite when a changed
  file has no mutation subjects on its changed lines, such as a deletion
  whose remaining context is blank or comment lines or a comment-only
  change: such files no longer require a guessed spec. And when some
  changed files still have no spec named after them, the run now narrows
  to the specs it found and warns, instead of running the whole suite.
  Guesses come only from files with a changed mutation subject, and when
  no changed file has one the run reports that there is nothing to mutate
  (fixes #268).
- Fixed failures under non-UTF-8 locales such as `LANG=C` when project
  paths contain non-ASCII characters. Git output, coverage maps, result
  caches, baseline logs and worker messages are now decoded as UTF-8
  regardless of the process locale. This prevents
  `Encoding::CompatibilityError` in the canary, baseline failure excerpts
  and worker results, and fixes `--since` silently skipping changed files
  with non-ASCII names. Paths are identity, not display text: the canary
  watch, `--since` diff parsing, source discovery and the run fingerprint
  retag locale-tagged bytes losslessly, so a tracked file whose name is
  not valid UTF-8 stays watched (its deletion still trips the canary) and
  keeps its exact bytes through selection. The canary and diff parser
  preserve path bytes rather than replacing invalid UTF-8 bytes; the
  cache, coverage-map and worker-message boundaries reject invalid UTF-8
  instead of rewriting it.

### Added
- `--since` warns when a changed Ruby file in scope has no subjects
  covering the changed lines, so nothing is mutated from it (#232). A
  silent zero-subject scope used to pass as a clean run. Comment-only or
  formatting-only changes within discovered methods are skipped without
  this warning; the run reports those skipped methods.
### Fixed
- An unexpected internal error now prints `saboteur: internal error (...)
  - please report it` and exits 3, instead of escaping as a bare stack
  trace with an accidental exit 1. The crash message is normalized to one
  bounded line first, and agent mode reports the same failure as agent
  JSON. The full backtrace is written to
  `<cache_dir>/internal-error.log` (default `.saboteur/`), which the
  message names, and printed to stderr with `--verbose`; an unset
  `cache_dir` or a failed write leaves the one-liner standing alone.
  The executable loads the crash reporter before the CLI,
  so a failure while it is loading, being built, or running gets
  the full report. Coverage setup and the reporter's own load happen before
  it, so those failures get only the bare normalized one-liner plus
  exit 3. When agent mode was requested but the agent reporter never
  loaded, a minimal standalone failure JSON in the agent reporter's
  schema (status `error`, verdict `tool_failure`, exit code 3)
  answers instead (#233).
- The install spec reads the README as UTF-8, so the suite also passes
  under `LANG=C`.
- Tool and test reads of files that can carry non-ASCII text are decoded
  as UTF-8 regardless of the process locale: the baseline manifest and
  preview receipt, `.rspec` option files, the custom-map duplicate scan,
  the installer's Gemfile and `.gitignore` probes (`.gitignore` is
  rewritten losslessly), and the JSON reads in the test helpers.
- CI now runs the suite on Ubuntu Ruby 3.4 with `LANG=C` and `LC_ALL=C`
  to catch locale regressions exercised by the tests. The job is advisory
  for now: it is not part of the required-check policy, and whether it
  gates is a separate maintainer decision.

## [0.6.0] - 2026-10-14

### Fixed
- `saboteur doctor`'s boot-file check accepts `require` and `hooks`
  paths with or without the `.rb` extension, so the README's
  `c.require = ["./config/environment"]` quickstart no longer fails
  the check (#257).

### Added
- `allow_db_hosts` config (#258): hosts you assert are disposable test
  databases. The Rails integration's local-database check accepts them,
  and its refusal names the setting. `saboteur doctor` surfaces the same
  refusal, naming the remote hosts, and after a successful boot prints
  each test database's host. `0.0.0.0` now counts as a local host: compose
  setups write it into database URLs, and connecting to it reaches this
  machine.
- `--guess-tests` now maps files in packwerk packs (any directory with a
  `package.yml`) to the spec inside the same pack, and maps
  `app/controllers` files to `spec/requests` specs (`users_spec.rb` or
  `users_controller_spec.rb`). It still names the changed files it could
  not match (#259).
- `script/preflight`: a local pre-review check on one exact base and head
  (#210). It runs the protected-path scope check, sign-off, SPDX headers,
  whitespace, RuboCop and the specs (fast or full mode), writes every harness
  output through a symlink-safe writer under `tmp/preflight/`, and takes
  check reports through harness-owned pipes rather than checkout paths.
  It is not CI and a pass is not an approval.

### Changed
- All built-in operators now run by default, including `range`, `operator_assignment` and `condition_negation`, which were opt-in in 0.5.0. Use `--exclude-operators` (or `c.exclude_operators`) to omit operators, or `--operators` (or `c.operators`) to select a smaller set. Exclusions win; each CLI list replaces its matching config list. This changes the default mutation set: counts, runtime, survivors and scores may change. Review CI thresholds and survivor baselines before adopting the new results. To retain the 0.5.0 default operator set during migration: `bundle exec saboteur run --exclude-operators range,operator_assignment,condition_negation`. To clear an exclusion set in config from the CLI: `bundle exec saboteur run --exclude-operators ''`.
- Breaking selection policy change: old `core`/`extended` tier names are refused with migration guidance. Policy version 2 binds effective operators and exclusions to cache/verdict identity, reports, score-history v2 and baseline evidence. Old baselines are incompatible and need a fresh reviewed proposal; unchanged mutation IDs stay stable.

## [0.5.0] - 2026-10-14

### Added
- Opt-in extended `range`, `operator_assignment` and `condition_negation` operators (#135). They run only
  when selected with `--operators`; the default core set does gain the new `chain_removal`
  operator (below).
- `whole_file` config: an opt-in list of subject ids or globs (for example
  `"Point#distance"`, `"Geometry::*"`). For those subjects the child evaluates the
  whole mutated file instead of re-evaluating the one method, so methods
  surgical re-evaluation refuses can be mutated. It applies to methods already
  found as subjects. The file's top-level code runs again in the child: load-time
  side effects repeat and constants it assigns are rebuilt. A surviving
  mutant whose definition a later definition in the file replaces is reported as
  unreachable, not survived. Off by default (Refs #138).
- `--matrix` (#132) runs every covering test per mutant and lists blind and
  redundant tests after the survivors.
- The 30-second heartbeat of the baseline and coverage phases now shows the examples finished so far, the percentage and a rough time left, read from the phase log, instead of only the elapsed time. (#56)
- Each finding in `--agent` output carries a `testHint` (`kind`, `text`, and for a
  comparison swap that differs only for equal or unequal operands, a `case`
  such as `left == right`) saying where a test could look (#154). It is a
  suggestion, not a diagnosis: a survivor can also be an equivalent mutant.
- `--max-timeouts N` and `--max-errors N` CI gates (count or percent of executed
  mutants). Exceeding one exits 1 with `exitCause` `maxTimeouts` or `maxErrors`.
  The covered score is already gated by `--threshold`. No Action input yet.
- A run that leaves a live survivor ends with a "Next steps" footer of command
  templates: replay (`saboteur run --id DIGEST --seed N`, to be combined with the
  run's own selection options), an ignore entry with the survivor's subject, and
  `saboteur run --agent` (#147).
- **Safety:** mutant children now run under a Landlock sandbox on Linux
  6.2+ (Landlock ABI 3) (#152): the child cannot create, write, rename,
  unlink or truncate files in the project tree except `tmp/`, the cache dir
  and the system temp dir, and inherited descriptors already open for
  writing elsewhere are closed before the sandbox engages. This is the
  third layer behind the hazard guard and the canary, and the first one
  that stops a destructive call before it acts. Landlock covers the
  filesystem only. On kernels 5.13-6.1 (ABI 1-2) `truncate()` cannot be
  restricted, and on kernels without Landlock there is no sandbox at all:
  both run with the guard and canary only, noted once. `c.sandbox = false`
  opts out (`/dev/shm` and `/dev/tty` are denied like any other
  ungranted path; `/dev/null` stays writable); `c.sandbox = "strict"`
  refuses to run degraded;
  `c.sandbox_writable` grants extra directories (suites writing `db/`,
  `log/`, ... otherwise fail with EACCES in mutant children) and warns when
  a grant contains the project root or another grant. The root check covers
  the effective write set - every grant realpath'd, the cache dir and the
  system temp dir included - so `cache_dir = "."`, a symlinked `tmp`, a
  `/` grant or a checkout inside the system temp dir cannot silently leave
  the tree writable; `c.sandbox = "strict"` refuses to run then. A kernel probe that
  errors (rather than cleanly reporting Landlock absent) refuses the run.
  The descriptor sweep also closes stdio redirected to a writable regular
  file (terminal, pipe and `/dev/null` stdio stays), inherited files
  already deleted from the tree, and any descriptor it cannot inspect -
  fail closed. The C library lookup tolerates musl (soname fallbacks, then
  the process symbol table) and degrades to the one-time unsandboxed note
  when no libc resolves, instead of crashing.
- Audited inline suppression comments with required reasons (#133). Inspired by mutineer
  (github.com/davidteren/mutineer, MIT, by David Teren).
- `--dry-run` previews planned mutants per method and the max_mutants_per_method
  omissions without booting the app, running tests, forking or writing reports
  (#134). A file that does not parse marks the total INCOMPLETE. A cached
  estimate is baseline covering-test work, not a bound on mutant runtime.
  Custom sources are still required during a dry run. `--list-operators` and
  `--operators` list and select builtin operators. Inspired by mutineer
  (github.com/davidteren/mutineer, MIT, by David Teren).
- [docs/minitest.md](docs/minitest.md) records that Minitest is unsupported and how much
  of the engine depends on RSpec (#200).
- [docs/scores.md](docs/scores.md) defines the covered score, the overall score a
  Stryker dashboard shows, assertion and crash kills, and what makes a run
  incomplete (#198).
- A startup warning on stderr when the working tree has uncommitted changes,
  because mutants run your code and could alter or delete files. Saboteur's own
  output paths do not count as changes.
- Terminal report rewrite: survivors grouped by file and method with
  evidence-scoped hints (suggestions, not diagnoses), a score table, a
  progress counter with ETA, `--verbose`, `--[no-]color` and `--fail-fast`
  (serial only; the run is marked incomplete with exit cause `failFast` and
  lists the subjects it never reached). The CI progress line-break can
  misalign by a mark when parallel workers finish at the same moment.
- Sorbet signature text does not prune nil-producing mutants. Runtime enforcement
  is not verified: checked levels, custom handlers and shims can allow nil to
  reach assertions. Type-aware pruning (#153) is deferred until enforcement can
  be established without guessing from return-type text.
- `endpoint_replacement` swaps explicit no-argument `first` and `last` calls,
  including safe navigation. Calls with arguments or blocks, bare calls,
  arid statements and nested scopes are excluded.
- The `chain_removal` operator drops one link from the middle of a method chain:
  `a.b.c` becomes `a.c`. The first receiver and the last call stay, so the result
  is still a call on the original object. It ships in the default core set; links
  that hand back their receiver (`freeze`, `dup`, `clone`, `itself`, `tap`) and
  chains that are assignment targets are left alone (#183).
- `saboteur baseline check|propose|accept --baseline PATH`: record today's
  survivors as a baseline file and fail only on new ones, so an existing project
  adopts mutation testing without a cleanup week. `check --epsilon POINTS` also
  fails when the score drops more than POINTS percentage points below the
  baseline's, and the failure detail prints inline. The GitHub Action exposes the
  drop as the `baseline-score-drop` output (#131, #148).
- `--guess-tests` scopes a `--since` run to the specs named after the changed
  files, for suites where full selection costs too much. A spec that reaches a
  changed file only through another file does not run, so a mutant only it
  would kill can survive, and a line no guessed spec executes is reported as
  NoCoverage. A changed source file with no matching spec (or no changed source
  at all) falls back to the whole suite with a warning. It cannot be combined
  with `--test` (#185).
- `--allow-focus` (#108): without it, a suite narrowed by a stray `fit`,
  `fdescribe` or `:focus` filter stops the run, because mutation testing a
  focused slice would report a score for the wrong suite.
- Survivor findings are ranked in the JSON and `--agent` findings: coarse
  mutants first, then more covering tests, a larger edited-line span and nearer
  changed lines (#191). The terminal report keeps its file/method/line groups,
  with the ranking applied within each live or accepted line group.
- `--score-history PATH` appends each run's scores to a JSONL file. Opt-in (#145).
- [docs/guides/reading-survivors.md](docs/guides/reading-survivors.md) is a guide
  to reading survivors, and [docs/recipes/README.md](docs/recipes/README.md)
  collects setups for factories, fixtures, DatabaseCleaner, Capybara and test
  adapters.
### Changed
- The text run prints one `Reports:` line naming the JSON and HTML reports, with
  paths relative to the project root when they are under it, instead of two
  lines with a blank line between them (#150). Scripts that read the old
  `JSON report:` and `HTML report:` lines must read `Reports:` instead.
- `saboteur doctor` checks the environment only by default (Ruby version,
  coverage setup and SimpleCov conflicts, boot files, the custom map and ignore
  subjects). The two unchanged baseline suite passes are slow on a large suite
  and now run only with `doctor --suite` (or `--test`, which implies it) (#53).

### Fixed
- `--since` with a ref that is not a commit exits 2 as a usage error, naming the
  ref, before the target boots. It used to exit 3 (tool failure) after boot (#115).
- Diff mode skips a method whose only changes are comments, blank lines or
  spacing, because its syntax tree matches the merge base. The run prints how many
  it skipped. A method that uses `__LINE__` is compared by the line it stands
  for, so moving it or adding a line above that use keeps it in the run.
  Ambiguous cases (a new file or method, a name defined twice, a base
  that does not parse) still run (#115).
- The default arid logger pattern also matches `@logger`, `self.logger` and
  `::Rails.logger`, so those calls no longer produce noise survivors (#111).
- The unscoped `--since` warning now says what `--test` drops: the consumer specs of a changed method no longer run, which can turn kills into survivors. (#113)
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
- Methods defined inside blocks (`Class.new do`, `Data.define do`, `included do`) are listed as
  skipped ("defined inside a block") instead of being silently absent. They are not mutated yet. `X = Data.define` / `Struct.new` / `Class.new` / `Module.new` with a block name X as the owner; any other block keeps the enclosing owner or "(anonymous block)". (#114)
- Endless defs (`def x = ...`) are no longer skipped as "no coverage": the
  coverage map now also records per-test method calls, which is how Ruby
  reports endless-def bodies. A whole-suite build that records neither a line
  hit nor a method call still stops with a clearer cause message. (#107)
- Mutants that compile to the same bytecode as the original method are dropped
  before they run, instead of surviving as untestable noise (#151).
- Mutants on branch arms that no covering test takes are skipped, using per-test
  branch coverage, instead of surviving as findings no test could kill (#184).
- Diff mode lists every survivor on a changed line instead of only one (#146).
- Methods with heredoc bodies select all of the method's tests again, and edits
  to pattern-matching arms map to the line that executes, so `--since` selects
  their killers (#130, #110).
- The empty-coverage error names Bootsnap only when Bootsnap is loaded (#149).

## [0.4.0] - 2026-10-12

### Changed
- The terminal report lists every survivor on a changed line in `--since` mode, instead of one
  plus "N more survivors on this line in the JSON report" (#146).
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
