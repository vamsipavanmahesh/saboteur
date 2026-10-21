# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.11.0] - 2026-10-21

### Added

- The colour contract palette: six tokens with overrides and CI-aware
  detection (#1112), the `c.palette` setting for text-report colour
  overrides (#1114), and one palette per stream wired from the CLI
  through the engine (#1117). The terminal report, score table and safe
  output (#1115), the survivor list and next steps (#1116), and the
  crash and failure exit lines (#1118) render with contract tokens.
- `run --baseline PATH` with `--epsilon POINTS`: an accepted baseline
  absorbs legacy survivors; only new survivors or a score drop beyond
  epsilon fail the run (#1120, #1121). The run tail reports matched
  counts, the gate verdict, and a re-baseline hint (#1122).
- `run --ignore-empty`: a zero-mutant `--since` diff exits 0 with a
  note (#1119).
- Quiet output: the terminal reporter gains a quiet mode - one line per
  finding plus the score line and verdict (#1126) - wired through the
  CLI as `--quiet` (#1133). Startup chatter moves behind `--verbose`
  and runs open with three quiet lines (#1134). Clean runs close with a
  success screen: win tally, untested note, and reports line (#1137),
  plus baseline, coverage and dots lines when phase data is present
  (#1139). Progress streams as width-sized glyph chunks on a redrawing
  terminal line (#1127).
- Survivors render as per-statement blocks with fenced source and
  killer-test details (#1136), built from prose templates and an
  edit-span helper (#1123). Each survivor shows which covering tests
  ran against it (#1106), survivor labels mark exception message edits
  arid (#1095), and an opt-in pass confirms survivors against the
  coverage map (#1089).
- The HTML report vendors and pins the mutation-testing-elements 3.9.0
  viewer (#1124), mounts it in the report (#1125) with an end-to-end
  smoke test (#1128), and names the changed line each mutant relates to
  in diff mode (#1110).

### Changed

- Exit-code split: a red baseline exits 5 and an internal crash exits
  70 (both were exit 3) (#1098), documented in the Action (#1099).
- The score is honest about untested subjects (#1104).
- The kill split counts cause-not-recorded kills and exposes them to
  agents (#1109).
- The README is rewritten as a top-tier dev-tool README.

## [0.10.0] - 2026-10-21

### Added

- Survivor labels in the terminal: surviving mutants carry a label and
  the findings collapse per statement, ignored mutants are reported with
  their reasons, and external-runner runs emit the `tool_limit` label
  (#1065, #1071).
- Pins covering the terminal collapse, the `--all-mutants` wiring, and
  the phase1 end-to-end default (#1065).

### Changed

- The terminal disambiguates the two no-coverage skip counts (#1087).
- `test_selection = :all` is gone: the 17 mirror-breaking files are
  mapped explicitly instead (#1077).

### Fixed

- The `element_removal` help text shows that any array literal works
  (#1086).

## [0.9.0] - 2026-10-20

### Added

- Five new mutation operators: `and_assign` drops the guard on `&&=`
  (#873), `jump_value` replaces unchecked early-exit values (#875),
  `rescue_removal` removes exception handlers no test reaches (#877),
  `when_removal` removes case branches no test takes (#887), and
  `unary_removal` removes signs and complements no test sees (#890).
- `--resume DIR` keeps verdicts in a directory across runs, with a
  manifest check on the directory (#840, #831), and `--incremental`
  checkpoints verdicts while the run is going (#820, documented in #822).
- Partial and parallel coverage: `c.coverage_parts` deals the suite into
  parts built in parallel (#741: #769, #772, #774, #776), keeps each
  finished part when a build stops (#860), and reuses the saved parts
  when a parallel build is rerun (#862). The partial map merge and an
  opt-in shadow run compare a partial rebuild against the full map
  (#829, #832), and `partial_coverage = "use"` skips the full build when
  only spec files or covered sources changed, rerunning just the stale
  spec files and merging them into the earlier map (#918).
- TracePoint coverage recorders: `MethodCalls` records Ruby method
  entries (#794, #795), a line-hits recorder reads branches once per
  spec file (#894, #897), and `c.coverage_recorder = "trace"` picks the
  TracePoint build (#898).
- Constant-reference spec selection: a spec that requires a spec-less
  file counts as its reference reader (#876, #879), a stop that keeps a
  hub file's cap says how many specs reference it (#881), and the agent
  JSON provenance reports and flags findings whose specs were chosen by
  reference (#884, #885).
- The GitHub Action posts surviving mutants as pull-request review
  comments on the lines the PR head has (#788, #789, #793), matches the
  review comment bot login without regard to case (#791), documents the
  review comment inputs (#790), and exposes max-timeouts and max-errors
  as inputs (#246, #767).
- Integration targets: a target can name its own gemfile (#900), carry
  patch, env and recorder options (#899), and run setup commands and add
  gems (#910). doorkeeper, paper_trail, cancancan and lobsters join the
  recorder-parity targets (#901, #908, #912).
- The JSON report adds per-gate score breakdowns (#473, #766) and a
  `saboteur.complete` field (#784).
- A real-bug corpus runner with a manual CI workflow, and the s-z and
  i-r corpus slices (#652: #915, #916).
- A coverage cache miss says why it missed and what changed (#812), and
  spec shards balance by recorded per-example run time (#747, #748).
- Warnings across the survivor, sandbox grant, shadow, worker, budget
  and `--since`/`--subject` messages lead with the outcome and name the
  remedy, per the documented message style (#332 series, #796).

### Fixed

- `--since` ignores a line whose only change is its trailing comment
  (#892, fixed in #921).
- `script/rspec-shard` no longer dies of SIGPIPE on a long spec list
  (#878).
- `or_assign` no longer mutates constant targets inside a def (#874).
- A test that suspends Coverage no longer breaks the map build; Coverage
  resumes after it (#869).
- Worker pool cleanup no longer leaks live entries or masks errors, and
  keeps unregistering workers when the orphan sweep goes blind (#762:
  #770, #771); containment and the live registry survive a blind process
  table (#762: #764).
- A timed-out Gemfile resolver no longer blocks on escaped-grandchild
  pipes, and the resolver-pipe specs reap escaped grandchildren (#734,
  #750). A `path:` source equal to the project root rebases onto the
  copy root (#729), external test-command `path:` sources are refused or
  rebased (#644, #721), and the BUNDLE_GEMFILE pin gaps close with
  lockfile-mismatch refusals (#732).
- A cached coverage map is read as untrusted input: its field types,
  durations and loaded files are checked, non-finite values are
  rejected, and the inputs snapshot binds to the map and the runtime
  (#853, #854, #859, #825). Stored verdicts are type-checked before
  reuse (#842).
- Cache files and the coverage map write through an exclusive private
  temp file (#846, #850).
- Registry DSL blocks in Ohai/Puppet style promote their defs to
  subjects (#700, #727).
- The baseline checks the unchanged suite in the coverage build's parts
  instead of a separate pass (#930).

### Security

- CI workflow-command injection is closed at every sink: the unmatched
  whole_file pattern (#856), repo-controlled file names in the
  constant-safety warnings (#857), name_list items (#858),
  repo-controlled names in the syntax, custom map and sandbox grant
  warnings (#870), every Diagnostics warning line (#871), the terminal
  report at one choke point (#872), the stop and gate messages (#919),
  and the CLI error sinks (#917, fixed in #920).
- The review comment planner is hardened against untrusted input (#783),
  and the Action fetches the pull request base with the token in a step
  of its own, with the token-handling scripts pinned (#797, #798).

### Documentation

- The getting-started guide shows a gem-installed run (#815), the
  config-key table documents every key and the Rails config points at it
  (#809), the Action guide documents a per-path score gate (#817),
  `--incremental` verdict saving is documented (#822), and the warning
  and note style convention is written down (#796).

## [0.8.1] - 2026-10-18

### Added

- Positional call-argument swap operator (#653): swaps adjacent positional
  arguments at call sites, catching specs that do not pin argument order.
- After the first timed baseline pass, saboteur projects the remaining
  baseline+coverage cost against `--max-duration` and warns up front when
  the budget barely fits or is exceeded, naming how much time mutants get
  and the remedies (#637). A `--max-duration` run that ends with exit 4
  and 0 mutants now headlines "no mutants ran", and the flag's help states
  what the clock covers: it starts at engine entry and includes the
  baseline and coverage phases.
- fiddle is no longer a hard dependency: it loads lazily through one door
  that refuses with every working fix named when it is missing, and the
  sandbox layers fail closed on refusal (#639).

### Fixed

- The DCO checks no longer disagree: CI's check-dco, preflight, and the
  panel gate all require the Signed-off-by line to be a real git trailer
  after a blank line (#646).
- When a changed file matches no spec by id hint, saboteur names the exact
  ids it looked for (`warn_unmatched_whole_file`, `--since` scoped) (#635).
- `saboteur pr --since` on a spec-only or docs-only diff no longer warns
  that "the whole suite runs" - it announces there is nothing to test,
  matching the zero-subject run that follows (#607).
- On macOS the degraded-sandbox message no longer claims the kernel "lacks
  Landlock (needs Linux 6.2+)"; it says macOS has no Landlock and points
  at `c.sandbox = "seatbelt"` (#667).
- The preset banner shows the effective flags, including explicit
  `--since` refs and flag=value spellings (#666).
- Running saboteur without rspec-core in the bundle (for example a
  Minitest project) fails as a usage error (exit 2) naming docs/minitest.md,
  instead of an internal error pointing at the RSpec-only `c.integration`
  remedy (#610). A baseline that fails with NoMethodError in a suite whose
  spec_helper requires minitest now warns the suite looks like Minitest
  running under RSpec, with the symptom and count (#626).
- Test-file guessing looks for specs below a flattened namespace
  (rubocop-ast style layouts) (#586), and when a layout strips directories
  between source and spec trees it picks the unique spec by parent
  directory and basename instead of failing or guessing wrong (#600).
- A `--subject` pattern that names an attr_reader, attr_writer or
  attr_accessor method no longer says "matches no subject"; the method
  exists but has no body to mutate, and the message says so (#373).
- Load errors in the target app's boot are reported with the tool's own
  frames filtered out, with `--verbose` restoring the full backtrace (#608).
- If a spec file loaded Ruby code before saboteur started coverage,
  whole-suite runs no longer report "5 subjects, 0 mutants"; saboteur
  names up to 5 preloaded files with cause and remedy and exits 3. With
  `--test` it warns and continues (#686).
- An empty or docs-only `--since` range exits 0 with a "nothing to test"
  notice instead of failing (#659), and a run no longer floods stderr with
  Ruby's "possibly useless use of nil in void context" compile warnings
  when the host suite enables warnings (#656).
- Running saboteur in a project with no RSpec suite stops with a single
  line naming the problem and pointing to docs/minitest.md, instead of one
  line per source file; specs outside spec/ fall back to the per-file stop
  with `--test`/`--all`. Exit code unchanged (2) (#606).
- Whole-file targets no longer error "already initialized constant" in
  strict-warning suites when the app lazily requires the same file (#632).
- Doctor's macOS degraded-sandbox output names the way out:
  `c.sandbox = "seatbelt"` with the guide link, or `c.sandbox = false` (#667).
- Load-time vetting no longer rejects `class << self` or `/re/.freeze`,
  and the constant-skip warning cites a one-line excerpt plus line instead
  of whole class bodies (#664). Vetting clears Struct/Data factories,
  public_constant/private_constant, and lambda literals so those files
  keep their mutation subjects (#537).
- A spec load that quits because the suite auto-starts SimpleCov/SingleCov
  names the suspect and both guard styles, instead of an opaque "No
  examples found" (#645).
- A sqlite :memory: database with a schema but zero rows hints at
  require-time seed data lost across the fork, with the
  before(:suite)/after_fork remedy and the `c.hooks` wiring (#594).
- The early-stopped summary headline reads selected versus attempted, for
  example "57 mutants selected, 4 attempted" (#582).
- The dirty-tree warning headline says "uncommitted or untracked change(s)"
  so a tree of only scratch files is not read as edits (#604).
- Custom-map load errors name unsupported template syntax before glob
  validation, literal map paths are preserved, and mixing numbered and
  named map templates is rejected at load with a clear error (#642).
- The sqlite in-memory database fork-loss hint includes the exact
  `c.hooks` configuration needed to load the suggested after-fork hooks
  file (#593).
- A subject the `--max-duration` budget stops mid-list no longer drops the
  kills it already measured: the truncated subject's completed kills are
  confirmed uncapped (#588).
- Shell-exported RUBYLIB entries that bundler's scrub drops are restored
  (#584), `spec/` is on the load path for non-Rails boots too (#615), and
  RSpec core loads before configured boot helpers so non-Rails helpers can
  call RSpec.configure (#616).
- `--test-command` warns when one ruby is handed several test files: ruby
  executes only the first, so the rest never ran and their mutants
  silently survived (#611).
- Dry-run excludes statically unsupported subjects, such as methods
  defined inside blocks, from planned mutant totals and reports the skip
  reason (#651).
- Non-String integration assignments fail with a file-and-line
  configuration error before fingerprinting or boot (#614).
- Baseline failures outside examples say so and show the log tail instead
  of an empty failed-example list (#581).

### Documentation

- The flaky-tests and survivors guides catch up with 0.8.0 (#683), and
  design.md explains the load-time vetting safelist for constant replay
  under `--since`, including what it cannot account for (#537).
- Docs drift: the pinned saboteur-vs-mutineer benchmark report names the
  version it measured (0.1.0), and the compare page scopes its kill
  re-check claim to fresh kills (#657).
- The README quick start covers the inference-miss exit 2 and its
  recovery, the install block leads with Bundler, the quick-start anchor
  matches its heading, and a no-warranty disclaimer joins the license
  section (#658, #657, #599).

## [0.8.0] - 2026-10-18

### Added

- `--test-command` runs a mutation-visibility check before the first
  mutant (#441). The command runs once with the first subject's file
  replaced by a load-time error; if it still passes, the command cannot
  see mutants in that file - a `RUBYLIB`/`-I` path or an installed gem
  anchors it to the real tree, or the suite never loads the file - and
  the run warns loudly that the score would read 0.0 % instead of
  silently reporting every mutant Survived.


- `--shard K/N` (#470): run one deterministic slice of the planned candidate
  inventory - `K` is the 1-based shard and `N` the number of shards. Each
  planned mutant is assigned by a SHA-256 of its candidate identity, never by
  position, so the split stays stable when an earlier subject gains or loses a
  mutant. The terminal, JSON and agent outputs name the shard, the inventory
  digest and the selected/planned counts, and a shard run is always reported
  partial. See docs/guides/sharding.md for the CI matrix setup.

- `saboteur survivors <report.json>` (#475): a read-only terminal browser
  for the Stryker JSON report - list and filter survivors (with the
  ranked-findings order available via `--ranked`), and `--show DIGEST`
  prints the diff, the exact replay command and an ignore-file entry
  template. It never boots the project or edits the ignore file.
- `--flaky-check survivors|decisive` (#476): one reordered confirmation
  rerun per new survivor (and per fresh kill in `decisive` mode). A
  verdict the confirmation disagrees with becomes `unverified` - named
  with its decisive tests, outside the score, never retried until it
  passes.
- `saboteur badge` writes Shields endpoint JSON from the opt-in score
  history and `saboteur trend` prints the covered-score delta against the
  last comparable record (#474). A README badge needs no hosted service:
  commit the written JSON and point a Shields endpoint badge at its raw
  URL. An incomplete run is refused as badge evidence unless
  `--mark-partial` labels the badge as partial, and the trend never
  compares records with different selection, inventory, schema version
  or operator policy.
- `c.sandbox = "seatbelt"`, an opt-in macOS sandbox for mutant children
  (#436): each child applies a Seatbelt profile (writes denied except the
  granted dirs, the system temp dir, and its own inherited logs) via
  `sandbox_init`, after a forked probe proves a deny-default profile
  really blocks a write. A macOS without Seatbelt degrades to the hazard
  guard and canary with a one-time note; an errored probe or a profile
  that does not enforce refuses the run (the Landlock probe's pinned
  semantics, #178), and a child whose profile refuses to apply fails
  closed instead of running the mutant.
  On Linux the value behaves like `true`. Opt-in because Apple deprecates
  `sandbox_init` without a published replacement; #436 tracks the
  ecosystem's response.
- `saboteur run --dry-run --format json` prints a versioned machine-readable
  mutant inventory without booting the suite (#469): schema version, run
  metadata, subjects, every planned mutant with its stable digest, operator,
  file, line and byte-range edits, and every skipped candidate with its
  reason (inline suppression, hazard refusal or the per-method cap).
  `--dry-run --agent` now names this flag instead of only refusing.
- A `regex_replacement` operator (#135): drops each regex anchor
  (`\A`, `\z`, `\Z`, `^`, `$`) in turn and swaps each bare `+` or `*`
  quantifier, so a validation like `/\A\d+\z/` finally gets mutants.
  Escaped characters, character classes and lazy or possessive stacks stay
  untouched; interpolated regexes stay out. The operator policy version
  moves to 3: histories stamped with an older policy stay readable but
  never trend-compare against new runs.
- Methods defined by a non-interpolated `class_eval`/`module_eval` heredoc
  are mutation subjects (#544): the heredoc body is re-parsed against the
  real file's bytes, so mutants inside it are generated and judged like
  ordinary defs (the faraday shape that used to produce 0 subjects). An
  interpolated heredoc still yields no subjects and keeps the
  code-in-strings warning (#467).
- Per-path score gate config (#473, slice 1): `score_gate "app/payments/**/*",
  min_score: 95` in `saboteur.rb` declares a per-subtree score floor,
  validated at load (min_score 0-100, pattern must match an included file).
  Enforcement lands with slice 2 (#570).
- Per-path score gates are enforced (#473, slice 2): each `score_gate`
  subtree from slice 1 (#565) is scored with the run's own formula. A gate under its floor fails the run like the
  count gates (`scoreGate` cause in the JSON report); a gate with nothing
  executed under it passes vacuously and says so. Score gates cannot combine
  with `--agent`, like `--threshold`.
- Peak-memory measurement (#202, slice 1): each worker reports its kernel
  peak RSS (VmHWM) when it retires, and the JSON report records it under
  `saboteur.memory` as per-worker `peakMb` values plus the supervisor's own
  peak. No total is printed: fork copy-on-write makes per-process RSS
  non-additive. The section is omitted where procfs is unavailable.

### Changed

- Any `--since` run whose resolved range has no changes now refuses with
  exit 2 instead of passing with 0 subjects (#643) - scheduled or no-op
  runs included. The common hit is `saboteur pr <merge_sha>` on a
  checkout AT the merge commit, which diffed the merge against itself;
  the refusal names the base and the resolved range and says to fetch
  the merge's parent or point `--since` at the change's base.
- A run whose effective include set selects no Ruby file now refuses with
  exit 2 instead of passing with 0 subjects (#447). The default include
  targets plain gems, so a first run on a Rails-shaped tree used to be a
  green gate that mutated nothing on every CI run; the refusal names the
  stale pattern and points at the install generator.
- A `--subject` pattern that matches no subject now fails the run (exit 2)
  instead of passing silently with zero subjects (#379). When some patterns
  match, the run keeps them and the summary names the missing pattern and
  the matched count.

### Fixed

- A single `using` anywhere in a file used to skip every subject in the
  file. Refinement skips are now scope-granular (#634): a bare `using`
  skips only subjects after it in its own class/module body (or the
  rest of the file at the top level), so one module's refinement no
  longer skips a sibling module's methods. A `using` inside a method
  or block body still skips the whole file.

- `scope :name, -> { ... }` and `define_singleton_method` bodies are now
  subjects (#194): the human-essentials dogfood showed a scope's lambda
  going unmutated. The call is a singleton subject of the enclosing owner;
  the lambda or block body mutates, and re-evaluating the whole call
  re-registers the method.
- An arid statement (a logging or instrumentation call) whose block carries
  real work is now mutated inside the block (#464). The walk used to skip
  the whole statement, so a method like one wrapped in
  `Notifications.instrument ... do |payload| ... end` produced only the
  coarse `body_raise` and no statement_removal, boolean_logic or other
  fine mutants on the changed lines. The block body is walked like any
  other, and such a statement also keeps the method out of the
  nothing-to-remove coarse check.
- A loaded class defining a singleton `hash` that does not return an
  Integer (forem's `ReactionCategory`) no longer crashes the boot as an
  internal TypeError: every `Coverage.result` read now refuses with a
  diagnostic explaining the violated `#hash` contract and blaming the
  application's code (#564).
- A `--since` diff that deletes a method no longer reports the deletion as
  "differ only in comments or formatting" and no longer names the method the
  deleted lines drifted onto. The run says what was deleted instead: `N
  changed subject(s) were deleted, nothing to mutate: ...` (#466).
- An error-dominated run no longer prints a bare score above the "tested almost nothing" warning: the terminal reports "score n/a (N of M mutants scored, X % of scored)" so the scored share cannot be misread as a run-wide score (#557).
- Preflight no longer refuses a precompiled Ruby (mise, ruby-build) whose
  binary tops the 50 MB evidence-document cap (#364): tool identity
  digests stream with an executable-sized bound instead. The cap for JSON
  evidence documents is unchanged.
- A missing `rspec-core` no longer crashes saboteur into the internal-error
  report with a bare `LoadError`: the RSpec integration refuses with
  "rspec is not in the bundle" and names the remedy, adding the gem to the
  test group or pointing `c.integration` at the suite's framework (#482).
  Only the framework's own `LoadError` converts; a `LoadError` raised by
  the app's own files, or for a different feature such as `rspec/core_ext`,
  keeps the crash route.
- A `--since` run whose changed methods were all skipped - refinements,
  no coverage, or any other skip reason - used to exit 0 with `score n/a`,
  a green run that tested nothing. It now exits 3 and names each skipped
  subject with its reason, and a partially skipped diff announces each
  skip up front instead of only in the end-of-run summary (#574).

- `saboteur badge` escapes incomplete-run reasons with `.inspect` in its
  refusal message, so a reason carrying newlines or control characters
  cannot spoof extra output lines (#474).
- `c.sandbox = "seatbelt"` grants now match real paths on macOS: the
  kernel resolves `/var` to `/private/var` when it checks a write
  against a Seatbelt subpath grant, so a granted dir under a symlinked
  parent (like `Dir.mktmpdir` under `/var/folders`) silently matched
  nothing and the child saw its own writable dir denied. Granted dirs
  are now resolved with `File.realpath` before the profile is built,
  the same view `fcntl(F_GETPATH)` reports back.

- The artifact dir now ignores itself (#426): a run writes logs,
  coverage maps and reports under the cache dir, and the marker
  `.gitignore` keeps a `git add -A` from committing them. An existing
  `.gitignore` there is left alone.
- Rejected kills no longer surface as generic errors: the terminal
  lists them in a `Rejected kills` section and annotates the error count,
  and report.json flags each rejected mutant with `rejectedKill: true`
  instead of carrying only the `rejectedKills` count (#375).

- A changed file the diff only deletes from no longer hard-stops a
  --since run for want of a spec (#484): a deletion-only file yields no
  subject and no fine-grained mutant, so test inference treats it as
  subjectless instead of demanding a spec, and the run goes ahead.
- The pr preset no longer hard-stops when a changed file's coverage
  lives in a consolidated spec the diff itself touches: a spec added
  or changed in the diff that reads a constant the uncovered file
  defines covers that file and runs, instead of exit 2 (#538). The
  stop remains for a mutable change no changed spec exercises.
- Dependency trees are never treated as changed source on a `--since`
  run (#504): a vendored bundle or `node_modules`, tracked or
  untracked, git-ignored or not, is rejected at enumeration, so the
  diff scope never lists, reads or warns on it. The `.bundle/config`
  file itself is project configuration and stays visible.
- The project-local bundler path (`.bundle/config`'s `BUNDLE_PATH`) now
  joins the dependency shield in its quoted and non-canonical forms
  (#567): matching quotes are stripped, an inline `#` comment is ignored
  the way Bundler::YAMLSerializer ignores it, a relative path is
  normalized against the project root, and an absolute path (the system
  bundle) stays outside the shield. A config that is not a regular file
  or cannot be parsed - including a NUL byte in the value - means no
  shield rather than a crash or a hang.

- A `--max-duration` budget that cannot cover the cold coverage map build
  now stops the run before the build starts, instead of spending the
  whole budget mid-build and keeping nothing - the trap where every
  `--incremental` resume redid the baselines and died at the same point.
  Once the baseline passes are timed, a build costing about one more
  full pass than the budget holds is refused up front, with the
  shortfall and the remedies (a higher budget, fewer
  `--baseline-passes`, or one unbudgeted run to warm the coverage
  cache) in the message (#427).

- The first-pass ETA no longer reads like a second baseline check when
  the baseline is done (#465): with a cold coverage cache the remaining
  pass is the coverage map build, and the message now names the coverage
  build and any remaining baseline passes separately.
- Def-time macro mutants - a `deprecate`-style helper, a `before_action`
  block, any DSL whose only caller is a class body - no longer report as
  survived: the closure captured while the app loads keeps the pristine
  definition, so replacing the method later cannot judge them. They now
  report as `ran at load`, outside the score (#409).
- A mutant on the continuation line of a multi-line interpolated
  statement is no longer misclassified missing_test (#498): attribution
  now spans the whole enclosing statement, because an interpolation's own
  statements are eager and Ruby's per-line events on continuation lines
  are not reliable per example.
- `--incremental` now sees dependency-declaration edits on projects
  that commit no lockfile (the library convention): the verdict
  fingerprint hashed only `Gemfile.lock` / `gems.locked`, so the digest
  was a constant and every cached verdict was reused across a `Gemfile`,
  `gems.rb` or `*.gemspec` edit (#408). Manifests and gemspecs anywhere
  under the project root are hashed always.

- A `--since` change inside a constant literal saboteur refuses to mutate
  (unvettable load-time code, or an unsupported literal form) no longer
  reads like an unexplained miss in the umbrella "no subjects covering the
  changed lines" warning: the warning now says how many of the files sit
  in a constant literal that is not mutated, named by the constant
  warnings above it (#537).

- ERB generator templates (`.rb` files with ERB interpolation, as Rails
  generators carry under `lib/generators/**/templates/`) no longer print a
  per-file "does not parse" warning on every discovery pass: they can
  never parse as plain Ruby, so they are skipped with one summarized note
  per run. A real syntax error in a plain Ruby file still warns per file
  (#372).
- A `c.sources` entry that looks like a source glob now fails with a
  pointer to `c.include` (#488): `c.sources` registers custom operator
  sources (`builtin` or `path.rb:ClassName`), not the files to mutate.
- A baseline stopped by a containment limit (process count or memory)
  now names the knob and its current value in the refusal (#459): a
  suite that forks heavily by design, or legitimately needs more
  memory, is pointed at `c.max_processes` / `c.max_memory_mb` instead
  of reading as a suite failure.

- A baseline that passed but leaked child processes no longer reads as a
  suite failure quoting an empty "Failures:" section (#486): the refusal
  says the suite passed, names each leaked process (pid and command,
  captured before the supervisor's kill) and skips the log excerpt, which
  only holds RSpec output.
- Engine setup load failures are reported clearly instead of as a bare
  quit (#378): when RSpec dies while loading spec files, the error names
  the files that failed to load, parsed from RSpec's own load-failure
  output, and suggests the remedy - exclude the broken subtrees with
  `--exclude-pattern` (for a Rails engine's embedded spec/dummy) or name
  the suite with `--test`.

- A spec file whose later examples rely on state left by earlier ones no
  longer turns its mutants into errors (#557). When a covering example
  fails even with the method unchanged, saboteur retries once with the
  file's examples in defined order, from the start through the last
  covering example. The kill stands only if that run passes unchanged.

- Spec and test files vendored under `lib/` (capybara ships its driver
  suite at `lib/capybara/spec/**`) are no longer swept into the default
  mutation scope (#504): the default exclude now shields
  `lib/**/spec/**`, `lib/**/test/**`, `lib/**/tests/**` and the
  `*_spec.rb` / `*_test.rb` / `test_*.rb` shapes under `lib/`. A config's
  own `c.exclude` replaces the shields wholesale, and the shields never
  trip the stale-pattern warning.

- A --since run whose changed lines sit inside a heredoc now says so
  (#467). Code embedded in a string - a class_eval/module_eval argument or
  a template constant - evaluates methods the static walk cannot see, so
  the generic "may not parse, or every change may sit outside a method"
  hint misdiagnosed it; the warning now names the files and the
  code-in-a-string blind spot.

- The "nothing to mutate" note on an empty selection now prints only
  once (#468). An empty-selection run already ends with the
  "0 subjects, 0 mutants" summary, and announcing the note again as a
  report warning at the end of the run read like a second failure; it
  is now a one-time inform when nothing has a subject.

- `--incremental` no longer reuses a stored verdict after the project source
  set changes: a file added after the coverage map was built (a conditional
  require, a Zeitwerk autoload) can load into a mutant run unseen, and the
  reused verdict read as a false green. The set is paths only; content edits
  to other files stay the documented cross-file tradeoff (#396).
- A factory assigned inside `class << self` now keeps its own scope in the
  owner path, so a constant defined there is named after the factory's
  singleton: `Host::W.singleton_class::V#n`. An outer factory with no
  `class << self` of its own still opens no scope, even when a `class <<
  self` encloses it (#438).

- A class factory assigned inside `class << self` no longer shares its
  method ids with a same-named factory in the class body (#406). The two
  unrelated classes each keep their own subjects: the singleton-side one is
  now named `Host.singleton_class::Widget#doubled`, so reports, `--subject`
  filters, ignore entries and the unchanged-syntax comparison can name it.
- `--test-command` keeps env-exported bundler settings the child needs:
  `Bundler.with_unbundled_env` strips every `BUNDLE_*` key, so a
  shell-exported `BUNDLE_PATH` (common in CI without a `.bundle/config`)
  left the child's bundler unable to find the app's gems and the run
  failed at baseline (#449). Values present in the pre-bundler
  environment are re-added; bundler-activated values and anchor keys
  stay dropped.
- `--test-command` no longer inherits bundler anchors (`BUNDLE_GEMFILE`,
  `BUNDLE_BIN_PATH`, `BUNDLER_SETUP`, ...) from a `bundle exec` parent or
  an exported shell environment (#435). The anchored child resolved the
  project gem from the real tree, never exercised the mutated copy, and
  reported every mutant Survived; the child now gets the unbundled
  environment and resolves its Gemfile from the mutated copy.
- Test selection consults `config/saboteur_custom_map.rb` again (#369).
  The map is the documented escape hatch for layouts the naming guess
  cannot match, but guess-tests never called it, so a mapped file still
  stopped the run as unmatched. A matching entry now wins over the naming
  convention, its specs run as the inferred ones, and an empty entry marks
  the file intentionally untested so it needs no inferred spec. The map is
  now documented in the README. Mapped spec values that are globs are
  expanded against the project root (the literal glob string never
  reached RSpec), a winning entry whose specs match no file stops the
  run with a config error naming the entry, and an empty entry's file
  is dropped from mutation with a named diagnostic instead of running
  the whole suite (#369 review).

- The marker sweep no longer kills a marked process it cannot identify
  (#389). A process that started before the run's root carries the marker
  only through an exec chain the run did not spawn, so it is left alone,
  and an escapee is signalled only when a fresh snapshot shows the same
  pid still owned by the same start time, so a recycled pid is never
  killed by mistake.
- The spec-name guess now tries the underscored require name of a dashed
  path: `lib/acts-as-taggable-on/x.rb` finds
  `spec/acts_as_taggable_on/x_spec.rb` (and the `spec/lib/` form) instead
  of stopping on an unmatched file (#383). The literal dashed name still
  wins when both exist.

- Factory-block subjects resolve to the right owner (#352). A class factory
  assigned inside `class << self` binds its constant on the singleton
  class, so re-evaluation now resolves a factory constant after a sclass
  scope there instead of raising "cannot resolve" for every mutant of its
  methods. And a constant or keyword class inside a factory block binds on
  the enclosing lexical scope: `FactoryProbe::Nested::RULES` and
  `M::HELPER` are now ordinary subjects under their lexical owner instead
  of a phantom `FactoryProbe::Outer::Nested::RULES` skipped as defined
  inside a block.
- Constants assigned inside `class << self` are now named with their real
  owner, the singleton class (`Host.singleton_class::RULES`), instead of the
  attached class (#380, #390). A same-named constant in the class body no
  longer collides with it or triggers a false "assigned more than once"
  refusal. Read matching follows: reads inside `class << self` still count
  toward the attached class's constant through singleton ancestry, and a
  singleton-class write shadows the attached class's constant for reads
  below it.

- A spec file that calls `exit` at load now refuses the run with a
  clear diagnostic instead of terminating the loader mid-require (#411).

### Changed

- The dirty-tree warning splits its count (#309, #316): changes inside
  the mutation scope (the Ruby files the configured include and
  exclude select; source operands narrow the run after the warning),
  outside it, and saboteur setup files (the config file the run reads, a
  `BUNDLE_GEMFILE` trial Gemfile and its lock), each as tracked and
  untracked, naming up to five scope and setup paths. The groups add up
  to the count. A tree of untracked notes or trial setup files no longer
  reads like application edits about to be mutated.
- A broken `.rb` symlink under `include` (dangling, a loop, or through a
  regular file) is skipped instead of ending the run with an internal
  error: it has no real path, so it is not mutation source (#503).
- The `each`/`map` method swap is no longer emitted where the call stands
  as a non-last statement (#399): its return value is discarded there, and
  both names run the same block, so the swap is treated as equivalent.
  The last statement of a body and calls nested inside an
  expression stay swappable, as does any call on a lazy receiver:
  lazy.map defers its block, so the swap is not equivalent there (#431).
  Only a `.lazy` in the receiver chain is detected: a lazy enumerator held
  in a variable, parameter or instance variable is not, and its swaps are
  suppressed.
  The discard analysis now recurses through branch tails: an each/map call
  that is the last expression of a discarded if/elsif/else/unless/case/when
  branch, begin/rescue body, or while/until body is suppressed too (#440).
- A `--since` run where only some changed files have a guessed spec now
  runs the mapped subset with a loud warning per unmapped file instead of
  stopping with "so nothing ran"; the stop message and the warning name
  same-basename specs found under `spec/**`, so the file can be passed to
  `--test` without hunting; a basename containing glob metacharacters is
  matched literally, never as a pattern. A run with no guesses at all
  still stops, as
  do full runs, `--subject` runs, and any run with a `--threshold` or a
  `--max-*` gate, since the gate would judge a score the unmapped file
  never joined (#370).

- A `--since` run now stops when every changed source file sits outside the
  include scope (#483), naming the hidden files and the ways out (extend
  `include`, or `--test` the specs). The old fallback ran the whole suite
  against zero subjects - the slow full run the `pr` preset exists to
  avoid - and its message read as if the diff had touched no source.

- The rerun and replay commands in the Next steps footer and the agent
  protocol leave out an empty `--operators` or `--exclude-operators` list
  that was not typed on the command line (#317): the config the command
  reads again supplies the same empty list. A typed empty list stays, since
  it may clear a configured value, and non-empty lists stay as before.
- `--since` no longer treats a line whose only change is layout as
  changed (#313). Wrapping existing statements in a block used to put
  every re-indented statement in scope; now only the new block lines and
  real edits get line-level mutants. A line is layout-only when
  `git diff -b` pairs it with a base line and Prism lexes both to the
  same tokens, so whitespace inside strings, heredocs and regexps, and a
  moved `__LINE__`, still count as changes.
- `--since` runs every spec file the diff adds or changes next to the
  inferred specs (#307). A request or controller spec whose name maps to no
  changed file used to be left out, so a mutant only it killed was reported
  as a survivor. A spec the diff adds beyond inference runs only when the
  configured RSpec suite loads it (its pattern, exclude pattern and default
  path) and it is a regular file; inferred specs run as before. A changed
  `*_spec.rb` that does not run, or that the diff deletes, is named with
  the reason, also before a stop on an unmatched file. `--test` and
  `--all` are unchanged.

- **Breaking change:** the pr preset no longer accepts a budget-stopped
  run by default. It exits 4; pass `--max-duration-ok` explicitly to
  accept the ordinary verdict. The terminal prints how many planned
  mutants did not run, or says the count is unknown when planning did not
  finish. (#654)


### Fixed

- A non-Rails suite that connects ActiveRecord to sqlite `:memory:` and
  loads its schema at require time no longer gets a bare "Could not find
  table" baseline failure (#387): every forked child reconnects to a fresh,
  empty in-memory database, so the child now detects that shape and the
  refusal names the cause and the remedies - move schema setup to
  `before(:suite)`, or load it in an `after_fork` hook (README recipe
  added). The Rails integration's per-child snapshot is unchanged.
- `saboteur run --test a_spec.rb b_spec.rb` refused: spec files in the source scope now fail as a
  usage error pointing at repeating `--test`, instead of a green run that mutates nothing; the
  `--since` "no subjects covering" warning names the misuse when every file is a spec file (#371).
- A mutant's test that daemonizes - forks an intermediate child that calls
  `setsid` and exits at once - no longer leaves a sleeping grandchild the
  supervisor never kills (#365). The tree poll can miss a descendant that
  leaves the process group and loses its parent between two polls, so
  every child now carries a unique marker in its environment (which
  reaches exec'd descendants) and in its comm via `PR_SET_NAME` (which
  reaches fork-only ones), and the end-of-run kill also sweeps the process
  table for the marker. Linux only for now; a self-renaming daemon still
  needs the CPU backstop.

- The Landlock ABI probe no longer flakes fail-closed with "Success -
  landlock_create_ruleset probe" on runners where the first errno read
  gets clobbered between the syscall and the read: the errno reader is
  built before the probe, and a failure return paired with errno 0
  (impossible from a real kernel answer) is probed once more. Genuinely
  unknown errors still fail closed.
- `rspec_args` that hold only options and their values (such as
  `["--require", "spec_helper"]`) no longer leave the suite with no
  files under `exe/saboteur`: RSpec adds its default path only when `$0`
  is `rspec`, and the value was taken for a path. saboteur now adds the
  default path whenever RSpec's own parse finds no file or directory to
  run, and a `--default-path` from `.rspec` wins over `spec`.
- `script/preflight` no longer loses why a git probe died: a probe
  whose child never ran git (the spawn failed, or a signal killed
  the forked child, as macOS does pre-exec under memory pressure)
  is retried once and, when it still fails, the error names the
  cause instead of printing an empty detail; a failure git
  reported itself is raised at once with git's own words (#319).

- The whole-suite empty-coverage guard no longer passes when the map holds
  spec-file lines only: the recorder maps the suite's spec files alongside
  the included files, and the guard checked whole-map emptiness, so a suite
  exercising none of the included files still recorded its own spec code
  and the run exited 0 instead of 3. The guard now checks each included
  file.

- Coverage-guided selection no longer drops a mutant's killing tests when a
  `case` has a `when X` arm whose body is bare `nil`: Ruby spans that arm
  from the `when` to the case's end, containing its sibling arms, and the
  recorder stored the span as-is, so edits inside the sibling arms were
  narrowed to the nil-arm's takers. Sibling arms are disjoint by
  definition; a span containing one of them is now rejected when the map
  is recorded (coverage map format 9).

- `script/preflight` full mode no longer rejects its own RSpec report: the
  fd3 shim now attaches a dedicated JSON formatter to the pipe instead of
  redirecting RSpec's output stream, so a project's progress formatter
  (`.rspec` `--format progress`) and spec output stay on stdout and cannot
  corrupt the report.

- `--incremental` no longer reuses a verdict when a file the covering
  tests touched changed: the dependency files from the run's coverage map
  join the verdict fingerprint (#197). The same holds for a dependency
  with only method coverage (an endless def), a file that ran while the
  app loaded, a loaded source the coverage map never observed, and a
  helper required lazily inside a test outside the include list, which
  the coverage build now records in the map so its changes invalidate
  verdicts too (#344, #353; coverage map format 10).
- `--test-command` survivors no longer carry the `missing_test`
  classification: the run's only recorded evidence is the pseudo-test id,
  which is not real coverage (#305).
- `--test-command` on macOS no longer refuses every tree containing an
  internal symlink: the disposable copy root is canonicalized before
  symlink targets are judged against it (/var vs /private/var) (#305).

- Suites that turn warnings into errors (`--warnings` plus a raising
  `Warning.warn` or `Warning.process` handler, dry-rb/hanami-style) no
  longer error every mutant: the re-evaluation's own "method redefined"
  notice is silenced while the mutant is installed, the same guard the
  whole-file strategy already had (#603).

- A mutant reported Survived when the suite itself replaced its
  definition mid-run: a `before(:each)` that re-loads the mutated source
  file (rolify-style `load "lib/..."`, #597) puts the original back
  before any test calls it, so every selected test passing proved
  nothing. The child now records which definition the mutant's
  evaluation installed and compares it with what is in place after the
  tests; a positively identified different def marks the mutant
  Unreachable (out of the score), never Survived, only when no test ever
  invoked the mutant, and the warning names the re-load site. A run
  where every mutant ends Unreachable exits 3 instead of going silently
  green. (#662)

- A scoped (`--since`) run that skips a subject for no coverage now
  names the loaded specs (or says none) and points at `--test`. Coverage
  in sibling spec files may not have been loaded; the existing exit-3
  gate is unchanged. (#636)


### Added

- guess-tests now tries the flattened spec root and a `spec/unit/` prefix
  after the mirrored guesses: `lib/pundit/policy_finder.rb` finds
  `spec/policy_finder_spec.rb` and `lib/aasm/base.rb` finds
  `spec/unit/base_spec.rb`, so `--subject` and `--since` stop hard-stopping
  on pundit, aasm and shoulda-matchers style layouts (#394, #370, #393).
- Methods defined in the four core class factories (`X = Data.define(...)`,
  `Struct.new`, `Class.new`, `Module.new` with a block) are mutation
  subjects instead of skipped subjects (#290): the finder names the
  generated class as the owner, and the mutant is re-evaluated through
  `X.class_eval`, leaving the generated class itself untouched. Defs in
  any other block stay skipped as "defined inside a block".
- `define_method(:m) { ... }` calls with a literal name and a block are
  mutation subjects (#194): the block body is mutated and the whole call is
  re-evaluated on the enclosing owner. A computed name, an explicit
  receiver, or a lambda argument stays unsupported, and a call in a block
  whose owner is unknown keeps the "defined inside a block" skip reason.

- A fault-injection e2e probe now pins cache-dir removal during the
  baseline window (#300): deleting `.saboteur` while the baseline holds
  the suite open changes neither the exit code nor the run evidence -
  later phases recreate the directory and the report holds the same
  verdicts; only the in-flight baseline log is lost. Other windows are
  not pinned to recover (a missing mutant log fails the run by design),
  so stop the run before deleting the cache, as `saboteur help` says.

- `saboteur doctor` now documents its version scope (#318): it certifies no
  versions of Rails, databases or application tools saboteur never invokes.
  A mismatched tool the suite loads still surfaces through the boot check's
  LoadError or the baseline refusal with the tool's own output; a narrower
  doctor check first needs the tool name, the expected and actual versions
  and the failure output, recorded on the issue.
- `--test-command CMD` / `c.test_command`: run an external command per
  mutant and take its exit status as the verdict - for apps that cannot
  load inside saboteur's Ruby. Serial, no coverage, unsandboxed. Mutants
  are applied in a fresh disposable copy of the tree per execution - the
  runner's own writes never touch the real files or follow symlinks - and
  the command's process group is terminated on every exit path. One
  budget-bounded neutral preflight checks the command on an untouched
  copy before any mutant exists; the shell's 126/127 read as setup
  errors, blank and non-string commands are rejected, and nested
  saboteur runs are refused (#140, #305). The preflight runs under an
  absolute deadline admitted after the tree copy, and a spent budget
  stops the run as budget-exhausted rather than a command failure.
  Internal symlinks are rebuilt as relative links inside the copy, so an
  alias sees the mutant while nothing can link out; escaping or looping
  links refuse the run. Copy and write failures become error outcomes
  with bounded context instead of crashing the run. Output capture is a
  bounded in-memory ring buffer, scrubbed to valid UTF-8 for reports,
  and its drain is time-bounded so a session-escaped descendant holding
  the pipe cannot stall the run. Subjects outside the project root are
  refused.
- Survivor classification labels in the JSON report (#192): each survivor
  carries `classification` - `likely_equivalent` when the mutant compiles
  to the original's instructions, `arid` when every line an edit touches
  matches an arid pattern, `missing_test` when a test covered the line
  and passed. The HTML report badges each survivor with the same label
  and the agent JSON carries it on each shown finding. Labels are
  heuristics for triage order only, never a diagnosis: scores and the
  exit code never change.
- `--since` mutates changed entries of constant hash and array literals:
  the assignments join the diff scope as subjects, `pair_removal` edits hash
  entries, the new default-on `element_removal` operator edits array
  elements (in methods too, so array literals grow mutant totals the way
  hashes do), and the tests are the specs covering a read of the constant.
  Unsupported forms (namespaced targets, `||=`/`&&=`, non-literal values,
  condition-guarded writes, or a constant written more than once in one
  file counting every write) are named in the diagnostics instead of being
  mutated or reported survived (#306).
- Constant replay vets the whole file: `--since` replays a constant's file
  only when its load-time code is limited to requires, pure defs,
  class/module nesting and literal assignments and trips no hazard denylist
  entry; anything else needs the constant listed in `c.whole_file` (the
  existing whole-file opt-in) or the literal moved into its own file.
  Constants whose only reads capture the value at load time elsewhere -
  including a capture inside a boot-time block - are dropped with a
  diagnostic. Spec files count as consumers: the coverage map records spec
  line hits, directory test paths and the default spec tree feed the
  consumer scan, `element_removal` honors the arid policy, arid patterns
  screen constant entries too, and constant mutation respects `c.sources`
  (no `builtin`, no constant mutants) (#306, #319).
- Constant replay hardening from the #319 lens review: `require` and
  `require_relative` count as vetted load code only with a plain
  literal-string argument and no block, so `require(build_path)` no longer
  reruns helper code on every mutant; rooted constant writes (`::RULES`,
  `::Shop::RULES`) share one identity with the bare write, and an
  unrooted qualified write (`Shop::RULES`) resolves through the lexical
  scope, so it demotes every literal on its scope chain it may overwrite
  (`Shop::RULES` inside `module Outer; module Shop` overwrites
  `Outer::Shop::RULES`); either way a re-assigning write demotes the
  first literal to unsupported instead of leaving it scored; the --all consumer scan reads
  the configured integration's loaded spec files instead of guessing the
  conventional spec tree; and an arid pattern that cannot judge an entry's
  bytes (binary source against a UTF-8 pattern) keeps the mutant instead
  of raising (#319).
- Fault-injection e2e specs pin exit 3 with a clear, test-blame-free message
  when the cache dir is read-only, is occupied by a regular file, or holds an
  unwritable baseline log (#251).
- A dropped mutation that does not parse is now named in the warnings with
  its subject and operator instead of only counting toward invalid
  mutations (#116).
- `docs/stability.md`: the agent JSON payload and the exit codes are stable
  public APIs with a deprecation process, pinned by a new contract spec; a
  governance note in CONTRIBUTING covers maintainer availability (#249).
- `saboteur doctor` says plainly on macOS that mutants run unsandboxed,
  advising a container for filesystem containment and network denial or
  stubbing for real-API risk, and the README carries a short per-platform
  sandbox and network statement (#247).
- Ignore-list entries accept a triage `state:` - `accepted_equivalent`
  (the default) and `wont_fix` suppress the survivor's exit failure (it
  still counts in the score), `todo` records the decision to fix and keeps
  the survivor counting as an unignored survivor. The HTML report badges the
  state; in the JSON report `accepted_equivalent` keeps the plain
  `ignored: <reason>` while `wont_fix` and `todo` are labelled
  (`ignored: <reason> (wont_fix)`, `todo: <reason>`), and all three keep
  status `Survived` (#155).

### Removed
- The stale self-deprecating benchmark claims in the README ('rerun
  pending'): speed and memory numbers now live only with the harness and raw
  data that reproduce them, or are framed as dated history (#243).

## [0.7.0] - 2026-10-16

### Upgrade notes
- Inferred test selection is now the default. Use `--all` or
  `c.test_selection = :all` to keep the 0.6.0 whole-suite behavior; use
  `--test` to name specs explicitly. Missing inferred specs stop before
  boot with exit 2. `--guess-tests` is now a deprecated alias for the
  default; `--no-guess-tests` warns and is ignored.
- Three new default-on operators change the mutation set, runtime and
  scores. Review survivor baselines and CI thresholds after upgrading;
  use `--exclude-operators` to omit operators you do not want.
- Harness integrations should handle budget-exhausted runs (exit 4),
  unverified mutants outside the score, and explicit JSON report write
  failures (exit 3). In agent mode, exit codes remain verdict-driven;
  budget exhaustion appears in `incomplete[]` and `earlyStop` instead.
  `--max-duration-ok` does not certify an unscored run.

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
- Report-artifact write semantics (#296): a failed HTML report or score
  history write now warns and lets the run exit by its results, so a
  read-only tree (a sandboxed child holding the project read-only) no
  longer turns a good run into a tool failure. An explicitly requested
  JSON report (`--json` / `c.json_report`) instead fails the run with
  exit 3 - it is the completion evidence an outer harness trusts, and a
  warning could leave a stale or partial file presented as this run's.
  The default `.saboteur/report.json` stays best-effort. Score-history
  soft failures are narrowed to the write's own IO errors; validation,
  integrity, record-size and lock failures stay hard errors.
- Crash-log fallback hardening (#296): when the cache dir cannot hold
  `internal-error.log`, the fallback in the system temp dir is created
  privately (`O_EXCL | O_NOFOLLOW`, mode 0600) instead of following or
  overwriting a pre-existing path. The pid-keyed fallback path is only
  computed after the primary write fails. Every crash log is now written private (0600) through a
  no-follow, non-blocking open - a planted symlink cannot redirect the
  write and a planted FIFO cannot block it - and the runner reads it
  back the same way, accepting only a regular file owned by the same uid
  with no group/other bits. Where the platform lacks `O_NOFOLLOW` or
  `O_NONBLOCK`, the primary log and the excerpt are omitted rather than
  opened unsafely; the `O_EXCL`-created temp fallback stays safe and can
  still be written. The appended
  excerpt is scrubbed to valid UTF-8 and labelled as freshness-matched,
  not certainly that run's.

### Added
- Dogfood/mutation diagnostics (#296): a rejected kill now reports why the
  killing test failed with the method unchanged - the exception class, its
  message and up to five backtrace frames, bounded to 2000 chars -
  instead of only the first line ("expected: 0"). Filtering frames whose
  paths contain `/gems/rspec` prioritizes project frames; the message and
  frame limits do not guarantee that the failing spec line survives.
  The terminal report
  prints the detail as indented continuation lines and the JSON report's
  `statusReason` keeps every line; one-line reasons are unchanged. An `unverified` verdict also keeps the runner's own
  reason (for example "the --max-duration budget is spent") rather than a
  generic one.
- Nested-run crash surfacing (#296): a spec that runs saboteur itself (the
  dogfood's own cli_spec) crashes the nested CLI as exit 3, and the crash
  lands in the run's internal-error.log. A child whose tests wrote a fresh
  log appends its first lines to the failure detail, so a verdict check's
  rejection includes crash context instead of only the exit-code diff.
  The excerpt is freshness-matched and may be from another run; it is
  not proof that this nested run wrote the log.
- `--max-duration` budget-exhaustion semantics (#296): a verdict check or
  timeout calibration the budget cannot admit is skipped rather than run
  with a zero-length timeout, so genuine kills are no longer misclassified
  as errors and cached. Admission is per check and per sequence: a check
  admitted with time left that hits its budget-shortened cap mid-check is
  `unverified`, not a rejected kill, later sequences never fork once the
  budget is spent, and unverified verdicts are never cached. Affected
  mutants report as `unverified` - outside the score - the early stop
  lists their subjects (`unverifiedSubjects` in the JSON report), and the
  CLI run exits 4 unless `--max-duration-ok` is set. Agent mode remains
  verdict-driven and records the budget in `incomplete[]` and `earlyStop`.
  Baseline checks and the coverage map build are now capped
  at the time left in the budget, and the early-stop reason comes from the
  actual truncation state, so mid-subject budget stops report
  `max_duration` even with `--fail-fast`. Agent output names unverified
  mutants in `incomplete[]`, and `--max-duration-ok` only passes a run
  whose verified verdicts (kills, survivors, timeouts) can carry a score.
- `saboteur pr [REF]` and `saboteur audit` presets: opinionated bundles of
  existing flags - the PR loop (changed lines since REF, one baseline
  check, a ten-minute budget with `--max-duration-ok`) and the audit
  preset (`--all`, all operators, two baseline checks, JSON and HTML
  reports). The PR preset opts out of the budget-specific exit 4, not
  normal or incomplete verdict failures. The audit keeps configured
  `since`, subjects, exclusions and budgets; explicit tests replace its
  injected `--all`. The run prints the expansion up front and explicit
  flags override it (#244).
- `--max-duration` (config `max_duration`, e.g. `10m`) budgets the whole
  run, baselines included: past the budget the run stops before the next
  subject, reports which selected subjects never ran, marks the JSON and
  agent output partial, and exits 4 in ordinary CLI mode;
  `--max-duration-ok` leaves the exit to the plain verdict (which can
  still fail the run). Agent exits remain verdict-driven, with budget
  exhaustion in `incomplete[]` and `earlyStop`. Works with
  `--jobs` by halting the worker pool (#245).
- `baseline_passes` (config and `--baseline-passes`) sets how many times the
  unchanged suite runs before mutation (default 2). `1` is the fast PR
  loop; the run announces that it gives up the order-stability
  comparison between passes, and the whole-suite cost message counts
  the configured checks (#55).
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
- Three new default-on operators: `method_swap` swaps a method with its
  semantic opposite (`min`/`max`, `any?`/`all?`, `map`/`each`; a receiver
  is required, so bare `max(a, b)` is untouched) (#237),
  `operand_replacement` replaces an arithmetic or comparison operation
  with each operand in turn (`a + b` yields `a` and `b`; boolean
  connectors stay with `boolean_logic`) (#238), and
  `interpolation_removal` removes each `#{expr}` and each literal segment
  of an interpolated string (#239). The hazard guard now also recognizes
  `send`, `public_send` and `__send__` with a literal symbol or string
  selector and applies the same checks as for the direct call to the
  resolved selector, with the arguments shifted past it: a destructive
  method name on any receiver (`helper.send(:rmtree, path)`), the
  configured hazard patterns, `Kernel#system` / `Process#spawn`, and
  `Kernel#open` with a "| command" argument all stay suppressed. Dynamic
  selectors stay out of scope as documented (#240).
- `--since` warns when a changed Ruby file in scope has no subjects
  covering the changed lines, so nothing is mutated from it (#232). A
  silent zero-subject scope used to pass as a clean run. Comment-only or
  formatting-only changes within discovered methods are skipped without
  this warning; the run reports those skipped methods. `--since` also
  warns when a changed Ruby file is covered by an include pattern but
  removed by `c.exclude`, naming up to five such files, so a too-wide
  exclude can no longer dogfood as a clean empty scope (#282).

### Fixed
- `--since` no longer skips untracked files silently (#295): a never-committed
  source file is invisible to `git diff`, so it used to contribute no changed
  lines and every subject in it was skipped without a word - even the
  changed-files-without-subjects warning could not name it. Untracked files
  now union into the changed-lines map as fully changed, so their subjects
  are selected, and one without subjects triggers the warning like any other
  changed file. Ignored (`.gitignore`), binary and empty files stay out, and
  only files inside the configured `include` set are considered, so a large
  unrelated untracked file is never opened. Each unioned file is opened
  `O_NOFOLLOW`/`O_NONBLOCK` and validated on that descriptor (a swapped-in
  symlink or FIFO is rejected and reported as unreadable), the binary sniff reads only the first
  few kilobytes, and the map holds a range of lines instead of one entry per
  line, keeping memory bounded. On platforms without those open flags the
  union is skipped with a warning.
- `--since` no longer drops an include-eligible untracked file quietly when
  it cannot be read (vanished, unreadable, or replaced by a link or special
  file between the listing and the open): the run names it in a warning and
  records it as a discovery failure, so an agent run over mixed tested and
  omitted source reports `partial`/`incomplete` with the `unreadable` reason
  instead of a clean result. Files that do not parse (`invalid_file_syntax`)
  surface the same way instead of only warning (#297).
- Include membership for untracked files is lexical first: an included path
  swapped to a symlink is attempted, rejected by the safe open and reported,
  instead of being filtered out silently on its resolved target. A symlinked
  repository root stays in scope through the canonical fallback (#297).
- Test inference under `--since` no longer enumerates a whole-file change
  range per method when deciding whether a changed file needs a spec; it
  answers ranges by interval, like the run's own subject selection (#297).
- The excluded-changes warning now also names untracked files in excluded
  territory: they never appear in the diff, so an exclude that removes one
  used to hide the removal entirely (#297).
- Distance and overlap checks over the whole-file ranges the untracked
  union produces are now geometric, so subject selection, test guessing and
  survivor ranking answer in O(1) per subject instead of scanning one entry
  per line of a large new file (#297).
- A baseline check or coverage map build that hit only its
  budget-shortened timeout failed the run as a suite error (exit 3) with
  no partial report; it now reports budget exhaustion with every selected
  subject unreached and exits 4 in ordinary CLI mode unless
  `--max-duration-ok` is set; agent exits remain verdict-driven (#296).
- The unscoped-suite warning pluralizes zero baseline checks correctly
  ("0 baseline checks", not "0 baseline check") (#296).
- Review hardening for the 0.5.0 loop flags (#245): the `--max-duration`
  clock starts when the run starts (boot, baselines and the coverage map
  all spend the budget) and is checked before dispatching every subject,
  between mutants inside a subject, and between baseline passes, in
  serial and `--jobs` runs alike; a parallel budget halt stops handing
  out new work and lets in-flight subjects finish and report, so their
  completed outcomes are kept instead of abandoned as nil holes
  mislabeled "never ran". `--max-duration-ok`
  no longer exits 0 when the budget stopped the run before any mutant
  was tested - there is no score to judge, so the run is incomplete
  (exit 3), in agent mode too. Agent output records `failFast` only for
  a real `--fail-fast` stop, `--baseline-passes 1` no longer certifies
  the suite stable in the baseline evidence, and the rerun/replay
  commands keep `--max-duration`, `--max-duration-ok` and
  `--baseline-passes`. `saboteur audit` bundles the `--operators all
  --baseline-passes 2` its help advertises, an explicit `--test`
  replaces its injected `--all`, and `--no-max-duration-ok` overrides
  the pr preset's budget pass.
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
  status as a kernel capability probe, not verified isolation: the
  Landlock ABI when the kernel can deliver it, the gap when it cannot -
  told apart as a `c.sandbox = "strict"` refusal versus the permitted
  degradation of a non-strict run - or off when `c.sandbox = false`. A
  probe the kernel refuses (EPERM under a seccomp policy) is an
  actionable tool error with exit 3, not an internal-error crash report,
  and doctor writes nothing (#236). The sandbox policy
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
  change: such files no longer require a guessed spec. A changed file
  that does need a spec but has none now stops before boot with exit 2,
  matching the default-inference policy above (#275).
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
  to catch locale regressions exercised by the tests. The panel gate's
  required-check policy includes this job (#281).

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
