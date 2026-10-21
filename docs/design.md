# saboteur design

Status: describes saboteur 0.3.x. Sections marked OPEN wait for a maintainer
decision; open work is tracked in GitHub Issues. Main is much newer: treat
the README (flags, exit codes, --agent mapping), docs/operators/ and
docs/scores.md as authoritative where they disagree with a section here.

## 1. Goal

Find tests that would not notice a plausible bug. saboteur makes a small
change (a mutation) to one method, runs only the tests that execute that
method, and reports mutations that no test fails on (survivors). A survivor
is either a missing test or code that does not matter.

Non-goals for v1: JRuby/TruffleRuby/Windows (no `fork`), mutating code outside
`def` bodies, LLM-generated mutations (the plug-in point exists; no source ships).

## 2. Pipeline

```
config + CLI
  -> boot target (parent, once)            hooks: before_boot, after_boot
  -> subject finder (Prism)                def bodies in included files
  -> subject selection / [--since] scope / [--id] resolution
  -> if selected subjects exist:
       BaselineGuard: two fresh whole-suite runs with the same seed
         failure -> abort, exit 5; no mutants started or per-subject skips
       CoverageStore.fetch (cached)         file:line -> [test ids]
       candidate selection: coverage, diff scope, validation, deduplication, cap
       serial or parallel distribution, per runnable subject:
         skip load problems; select covering tests
         coarse mutants first, then all eligible fine mutants
           each: reuse a verdict or fork -> re-eval mutated def -> tests -> status
           coarse verdict never suppresses fine candidates
         check fresh kills/timeouts against the unchanged method
       save eligible incremental verdicts
  -> reporters: terminal, Stryker JSON; ignore list applied; exit code
```

## 3. Parsing and subjects

- Prism parses each included file. Ruby 3.3 bundles prism 0.19, whose API
  predates 1.0, so the gemspec depends on the prism gem `>= 1.2, < 2`.
- Subject = one `DefNode`: instance methods and `def self.x`. Methods inside
  `class << self` count as singleton methods of the enclosing class.
- `define_method(:m) { ... }` with a literal name and a block is a subject
  too (#194): the block body is the method body, and re-evaluating the whole
  call redefines the method on the enclosing owner. A computed name, an
  explicit receiver, a lambda argument, a second argument (with two
  arguments the second is the body and the block is dead code), or no
  block cannot be named, and a call in a block whose owner is unknown
  stays skipped ("defined inside a block").
- Two class-level call shapes are singleton subjects the same way (#194):
  `scope :name, -> { ... }` (the Rails scope shape: literal name, one
  lambda) and `define_singleton_method(:name) { ... }` or
  `define_singleton_method(:name, -> { ... })`. The lambda or block body is
  the method body; the whole call re-evaluates on the owner, re-registering
  the method. Symbol-only calls, computed names and extra arguments define
  nothing saboteur can name.
- A `class_eval`/`module_eval <<-HEREDOC ... HEREDOC` call with a
  non-interpolated heredoc contributes its defs as subjects of the enclosing
  owner (#544): the heredoc body is re-parsed in place (everything outside
  it blanked, newlines kept), so offsets and lines stay the real file's and
  mutants apply through the ordinary byte path. An interpolated heredoc has
  no 1:1 byte map and stays on the code-in-strings warning (#467).
- Subject id: `Outer::Klass#meth` or `Outer::Klass.meth`, from the lexical
  nesting Prism reports (ModuleNode / ClassNode / SingletonClassNode chain).
- Skipped in v1: DSL calls in a class body, constants, code
  that runs when the class body loads, `def` nested in another `def`, methods
  defined inside blocks (e.g. `Class.new do ... end`, `included do ... end`),
  and `def` in a file with no enclosing class/module (top-level `Object` methods).

## 4. Making mutations: byte-range edits

A mutation is a list of `Edit(file, start_byte, end_byte, replacement)`
against the original file text. Offsets come from Prism `Location#start_offset`
/ `#end_offset` and are byte offsets, so all slicing uses `String#byteslice` on
the file as read from disk.

To apply: take the subject's `def ... end` byte range, apply edits (sorted,
non-overlapping, all inside that range), and get the mutated method text.

Why not parse -> modify AST -> print back:
- Comments, heredocs, formatting and line numbers survive untouched, so a
  reported diff is exactly the change made and backtraces point at real lines.
- No unparser dependency and no round-trip bugs.

Cost: each operator must produce text that still parses. Every mutated method
text is re-parsed with Prism before it is run; parse errors are dropped and
counted (not reported as survivors). Expected rate is near zero; we measure it.

Mutation identity (for the ignore list): SHA-256 over subject id, operator,
and for each edit (offset relative to the subject start, original bytes,
replacement), truncated to 16 hex chars. Relative offsets keep ids stable when
code above the method changes. Any edit inside the method that shifts the
mutated bytes changes the id; that is deliberate (the ignore reason may no
longer hold).

## 5. Operators (v1)

Only the v1 set lives here. Everything shipped since - endpoint_replacement,
range, operator_assignment, condition_negation, method_swap, operand_replacement,
interpolation_removal, chain_removal, element_removal, regex_replacement -
is documented under docs/operators/.

Coarse (run first per subject):
- body -> `nil`
- body -> `raise`

All eligible fine mutants run after the coarse mutants, regardless of whether
a coarse result survives, is killed, times out, errors, or is reused from cache.
Coarse-first ordering gives early feedback and seeds killer prioritization;
it does not gate fine execution.

Equivalent coarse mutants are not generated: no `body -> nil` for a body that
is empty, a lone `nil`, or only arid statements (logging); no `body -> raise`
when the method's own rescue catches `StandardError` (the raise is what the
rescue is for). Fine execution is independent of these coarse results.

Fine:
- Comparison (sufficient set, Kaminski et al. 2011): `<` -> `<=`, `!=`,
  `false`; `<=` -> `<`, `==`, `true`; `>` -> `>=`, `!=`, `false`;
  `>=` -> `>`, `==`, `true`; `==` -> `false`, `true`; `!=` -> `true`,
  `false` (not `<=`/`>=`: they raise on non-Comparable objects).
- Boolean (sufficient set, Just et al. 2012): `a && b` -> `a`, `b`,
  `false`; `a || b` -> `a`, `b`, `true` (same for `and`/`or`). Just's fourth
  mutant (`a == b` / `a != b`) is left out: with Ruby truthiness the operands
  are rarely booleans, so equality between them is not the logical relation
  the proof assumes; drop
  `!`/`not`; condition -> `true`, condition -> `false` (for
  `if`/`unless`/`while`/`until`/ternary predicates).
- Predicate methods (`def x?`): coarse `body -> true` and `body -> false`
  replace `body -> nil` (nil and false are both falsy; true was missing).
- Arithmetic: `+`<->`-`, `*`<->`/`, integer/float literal n -> n+1, n-1, 0
  (skip the replacement equal to n).
- Statement removal: each statement of a sequence of two or more, one at a
  time. Not for single-statement slots (the whole body is covered by
  `body_nil`; ternary branches, interpolation and modifier bodies are
  expressions), and not for an if/unless without else (the condition
  mutants make the same change).
- Nil handling: `x&.y` -> `x.y`, `a ||= b` -> `a = b`.
- Literals, filters and arguments (added after v1): boolean and string
  literal replacement ([literal operators](literal-operators.md)), `select`
  <-> `reject` polarity ([filter operators](filter-operators.md)), call
  argument removal ([argument removal](argument-removal.md)) and hash or
  keyword pair removal ([pair removal](pair-removal.md)).

Arid lines: a statement whose source matches a configured pattern is never
mutated and never removed. Defaults: `puts`, `pp`, `p`, `print`, `warn`,
`logger.*`, `Rails.logger.*`, `*.instrument`, `StatsD.*`. Configurable as
regexes over the call receiver/name.

## 6. Execution

Parent:
1. `before_boot`, start `Coverage` (only for map building), boot app
   (`require` the configured boot file), adapter `setup` loads test files,
   `after_boot`.
2. For each mutation: `before_fork`, `fork`.

Fork hygiene (parent):
- Coverage is not running in the parent during mutation (it lives only in
  the map-building child).
- Before each fork the parent holds no open DB/Redis sockets, except in-memory
  SQLite pools, which stay connected so the schema survives: Rails
  integration disconnects the other pools after boot; `before_fork` is the hook for
  anything else. The child opens fresh connections in `after_fork`.
- Threads do not survive fork, and a mutex held by another thread stays
  locked in the child. The parent must be effectively single-threaded at fork
  time; saboteur warns once, after the baseline and coverage children have run and
  before the first mutant fork, when `Thread.list.size > 1`.

Child (forked by `Execution::Supervisor`, see 6.3):
1. Mark itself (`SABOTEUR_CHILD=1`), own process group, CPU limit, parent
   watch.
2. `after_fork` (DB reconnect etc.).
3. Re-evaluate the mutated method (see 6.1), restore visibility (6.2).
4. Write `started` to the result pipe (`Execution::Protocol`, versioned
   JSON lines).
5. `around_mutant { adapter.run(test_ids) }`.
6. Write result to the pipe, `exit!` (skip at_exit handlers of the target).

Mutated source is never written to disk in the target project.

### 6.1 Re-evaluation

Spec'd approach: `owner.class_eval(src, original_file, original_line)`.

Measured problem (Ruby 3.3.4): string `class_eval` gives the code a lexical
scope of `[owner]` only. Constants defined in an enclosing module are no
longer found:

```ruby
module Outer
  LIMIT = 18
  class Person
    def adult? = @age >= LIMIT
  end
end
Outer::Person.class_eval("def adult? = @age > LIMIT", __FILE__, 5)
Outer::Person.new(18).adult?
# => NameError: uninitialized constant Outer::Person::LIMIT
```

Nested `module A; class B` style is the norm in gems and Rails apps, so
with the spec'd approach most subjects would fail the neutral check (marked
skipped) or show NameError during mutant runs. The neutral check would catch it,
so no wrong "killed" results, but coverage of the tool would collapse.

Proposed fix (keeps line numbers and the no-disk rule): rebuild the original
lexical nesting from Prism and evaluate it on ONE line at top level:

```ruby
eval("module Outer; class Person; #{mutated_def}; end; end",
     TOPLEVEL_BINDING, original_file, def_start_line)
```

- Reopening uses the exact constant-path tokens from the source
  (`class A::B` stays `class A::B`, which gives the same scope as the original).
- `class X` reopens without a superclass, which Ruby allows for an existing class.
- `class << self` is reproduced as written.
- The mutated def keeps its own newlines, so line N of the method is still
  reported as line N of the file. Columns on the first line shift; nothing
  depends on them.
- Verified in the same experiment: the wrapper resolves `LIMIT` correctly.
- Magic comments do not carry into `eval` (measured: a method from a
  `# frozen_string_literal: true` file returned an unfrozen string after
  re-eval). The evaluated string starts with the file's magic comments on one
  line and is evaluated at `def_start_line - 1`; measured to restore both
  frozen literals and `source_location`.
- Resolve the owner constant (`Object.const_get(path)`) before evaluating the
  wrapper. Under Zeitwerk this triggers the autoload first; otherwise `class Foo`
  in the wrapper would define a fresh shadow class.
- Class-factory blocks (`X = Data.define(:x) do ... end`, likewise
  `Struct.new`, `Class.new`, `Module.new`) name X as the owner, and the
  wrapper for that scope is `X.class_eval do`, never `class X`: a generated
  class must not be reopened (`Module.new` does not even produce a class).
  Their defs are ordinary subjects (#290); a block nested deeper still marks
  its defs skipped as "defined inside a block". The `X.class_eval` wrapper
  does not preserve the factory block's lexical constant scope: a constant
  assigned or a class declared inside a factory block binds on the enclosing
  lexical scope (`Outer = Class.new do Inner = ... end` makes
  `FactoryProbe::Inner`, never `FactoryProbe::Outer::Inner`), so factory
  scopes join a def's owner but never a nested constant's path (#339).
  A `class << self` scope joins a constant subject's owner as
  `<attached>.singleton_class`, matching where Ruby binds the constant (#380).
- Refinements (`using`) are lexical and are lost. A bare `using` skips the
  subjects after it in its own scope (the rest of the file at the top
  level); a `using` in a method or block body still skips the whole file
  ("refinements", #634).

Both are implemented (`reeval: nesting | class_eval`). Default: `nesting`
(maintainer decision M1, 2026-10-09). Measured skip rate from the lost
lexical scope (neutral check fails): 3.8 % of mutants on dry-inflector and
80.1 % on tty-color with `class_eval`, 0 % with `nesting`
(docs/validation/phase-2-gems.md). Recommendation: `nesting`.

Load-time vetting for constant replay (#319, #537, #664). A constant mutant
re-evaluates its whole file, so whatever the file runs at load runs again on
every mutant, outside the method hazard guard. Before replaying a changed
file, saboteur vets its load-time statements against a safelist:
`require`/`require_relative` with a plain string and no block, pure defs, class/module
nesting with a constant superclass, `class << self`, bare
`public`/`private`/`protected` (no argument, literal symbols, or
`private def x`), `private_constant`/`public_constant` with literal names,
`Struct.new`/`Data.define` with literal arguments and no block, and constant
or local assignments of plain literals (a `.freeze` is looked through; a
lambda literal is data). A file running anything else at load is not
replayed: its constant subjects are skipped with a warning naming the
unrecognized lines, unless the constant is listed in `c.whole_file`.

What the safelist cannot account for:

- Computed factory arguments. `Struct.new(*FIELD_NAMES)` or
  `Struct.new(names)` builds the member list at load, so the vet cannot see
  it; only literal arguments are vetted.
- Factory blocks. `Data.define(:x) do ... end` runs the block at load;
  vetted factories take no block.
- Non-literal visibility names. `private name` through a variable or method
  call, or `private_constant CONST`; only literal symbols (and
  `private def x`) are vetted.

These forms are not unsafe, only unvetted: saboteur cannot tell what
re-running them does. List the constant in `c.whole_file` to replay the file
anyway, or move the literal into its own file. Mutating the classes the
factories generate is #290.

### 6.2 Visibility

Re-defining a method with `def` makes it public (measured: a private method
became public after `class_eval`). Before re-evaluation, record
`private_method_defined?` / `protected_method_defined?` on the owner (singleton
class for `def self.x`) and re-apply `private`/`protected` after. Also handles
`private def x`, `private :x`, and `private` sections.

Known gaps (documented, not fixed in v1):
- `module_function`: the module-level copy is a separate method; mutating the
  instance method does not change `Mod.x`. Detect and re-apply `module_function`.
- `alias`/`alias_method`: aliases of the current definition (same source
  location) are pointed at the re-evaluated method, keeping their own
  visibility. An alias taken before the method was redefined keeps its
  older body on purpose and is left alone.
- Methods replaced at runtime (prepended modules, `Module#prepend` wrappers)
  still work: we redefine on the original owner and the prepend chain calls it.

### 6.3 Containment: timeouts, resource caps, process trees

Invariant: no process started on behalf of a child outlives that child's
supervision. A process group alone does not give this: any descendant can
call `setpgid`/`setsid`. A saboteur run started by a test inside a mutant
child did exactly that, and the escaped orphans (some allocating ~300 MB/s)
froze a 36 GB development machine twice (root cause in commit 47b8bc8).

`Execution::Supervisor` enforces the invariant for mutants, verdict checks
and the coverage-map child alike:

- Tracks the whole descendant tree (`Execution::ProcessTree`) by parent link
  and by the child's process group, rebuilt from the process table on every
  poll, remembering every pid ever seen (pid + start time, so a recycled pid
  is never signalled).
- After every child, whatever its outcome: SIGSTOP every member until no new
  member appears (a stopped process cannot fork), then SIGKILL them all.
  Survivors of a normal exit are reported as leftovers (a warning).
- While the child runs: a deadline (per mutant `max(timeout_factor x the
  recorded durations of its tests, timeout_min)`, defaults 3 and 5 s), a cap on memory growth across the tree (default 2 GB) and
  a cap on process count (default 64). The coverage-map child gets
  `coverage_timeout` and 4x the memory cap.
- Kernel backstops for what tracking can miss (a double fork faster than a
  poll): `RLIMIT_CPU` set in the child, inherited by every descendant even
  after it escapes; a parent-death check in the child (macOS has no
  PDEATHSIG); on Linux the supervisor is a child subreaper, so orphans stay
  in its tree.
- The parent kills every live tree on INT, TERM and exit.
- Recursion guard: `Engine` refuses to start in a process marked
  `SABOTEUR_CHILD`, so a test that runs saboteur fails (and the mutant is
  killed) instead of starting a nested run.

Measured on macOS 14: `RLIMIT_AS`/`DATA`/`RSS` cannot be lowered below a Ruby
process's reservation and are not enforced, so memory is capped by polling;
`RLIMIT_CPU` is enforced.

### 6.4 Statuses

| status    | meaning                                                         |
|-----------|-----------------------------------------------------------------|
| killed    | `started` received and at least one selected test failed         |
| survived  | `started` received and all selected tests passed                 |
| timeout   | deadline passed; tree killed |
| resource_limit | the tree hit the memory or process cap; tree killed; outside the score |
| error     | child exited/crashed before writing `started`, or adapter itself raised |
| skipped   | not run: no covering tests or a load/subject restriction |

`error` is never counted as killed. Skips carry a reason. A child that dies
after `started` without writing a result is `error`: from outside, a crash in
the harness looks the same as one caused by the mutation. The child rescues
`SystemExit` from test code and reports it as a normal failed run, so
`exit` inside a test still counts as killed.

A run where the adapter executed a different set of examples than requested
(count or ids differ) is `error`, never survived. This guards against a broken
filter turning every mutant into a false survivor.

Mutation score = (killed + timeout) / (killed + survived + timeout). Timeouts
count as detected (Stryker convention) and are shown separately. Errors,
resource-limit stops and skips are outside the score and always shown, so a
harness problem or a runaway mutant cannot raise the score silently.

## 7. Test selection: coverage map

- The map is built in a forked child, never in the parent. The parent boots
  and loads tests but never runs a test, so every mutant child forks from a
  process with no test side effects (DB rows, class state, mocks). The
  map-building child sends the map back over a pipe.
- Coverage is set up (suspended) in `lines` mode by the executable, before
  anything of the target loads. If `Coverage` is already set up (SimpleCov),
  saboteur refuses to build the map and says to disable it for the run.
- The map-building child resumes Coverage and runs the full suite once, test
  by test, calling `Coverage.result(stop: false, clear: true)` around each
  test; every line with a count > 0 maps to that test id. Coverage is
  suspended while the recorder processes each delta, so its own work is never
  attributed to a test. Each test's duration is recorded too.
- Lines hit outside any test (`before(:all)`, `before(:suite)`, lazy loads)
  are attributed to every test in the file of the next test that starts.
- A subject's tests (used by its coarse mutants) =
  union over the body lines of its `def` (excluding the `def` line for
  multi-line methods, since that line runs at load time; one-line and endless
  defs use the def line).
- A fine mutant's tests = the tests that executed its edit: the lines from
  the first line of the innermost statement holding the edit to the edit's
  last line (a statement's first line always records a coverage event when it
  runs). An edit outside every statement uses the subject's tests. A mutant
  whose edit no test executed is "no coverage", not a survivor.
- Diff mode (`--since`): subjects are the methods with a changed line; each
  keeps its coarse mutants, but fine mutants only on changed lines. The
  terminal lists every survivor, grouped by file, method and line; the JSON
  report holds the same ones.
- Incremental mode (`--incremental`, opt-in): a stored verdict (killed,
  survived, timeout) is reused while the method's source and its whole
  file, the mutant, the set of covering tests, their files' contents,
  every project source the coverage run loaded - including helpers
  required lazily inside a test, outside the include list - the shared
  spec helpers and boot files, the declared data inputs (fixtures, schema
  dumps, database and config YAML), the dependency manifests and lockfile,
  the verdict-relevant config and the saboteur version are unchanged.
  Adding or deleting any project Ruby file also invalidates every verdict. When every verdict
  of a method is reusable, nothing forks. Watching covers Ruby sources
  and the declared data inputs: a change to any other non-Ruby file
  outside that set (a locale file, a template) is in no fingerprint, so
  rerun without `--incremental` after touching one, or add its pattern to
  `fingerprint_extra` - `--no-cache` only rebuilds the coverage map and
  still reuses the old verdict. Run without `--incremental` now and then anyway (and in CI
  on the main branch).
  Verdicts are also saved about every 30 seconds during the run, through a
  temp file renamed into place, so a run killed mid-phase keeps what it
  finished (#471). Those mid-run saves are best effort (a failed one is
  retried a save interval later); the final save still raises.
- Order: tests that killed earlier mutants of the same subject first, then
  fastest first (suite order breaks ties). With fail-fast, a mutant is killed
  by its cheapest killing test. The verdict check (section 8) re-runs the
  exact sequence each kill ran.
- Cache: `.saboteur/coverage-<sha256>.json` keyed by the hash of every
  included source file, every test file, the lockfile, the resolved config
  (boot files, integration) and the saboteur version. Any change rebuilds.
  (Per-file incremental update is a later optimisation.)
- No covering tests for a subject -> all its mutants "no coverage".

Trade-off: test-by-test coverage collection costs one full suite run with
coverage on (measured once: 1.7x on human-essentials, 260 s vs 155 s; see
[the Rails validation](validation/phase-4-rails.md)), paid once
per cache key.

## 8. Verdict check (replaces the neutral check, 2026-10-10)

A false kill happens when a test fails for a reason other than the mutant:
the re-evaluation itself breaks something (6.1), or the test depends on
state left by an earlier test in the same child. A false timeout happens
when the tests are slower in a child than they were while the map was built.
Survivors cannot be false in this way (a broken re-evaluation makes tests
fail, not pass; a re-evaluation that does nothing is caught by the load
check, section 6.1).

So after a subject's mutants run, `Engine::VerdictCheck` re-evaluates the
UNCHANGED method the same way and re-runs only the evidence:
- each kill: the exact tests the mutant ran, in order, up to and including
  the killer (once per distinct sequence; killer-first ordering makes most of
  them one test). If that fails, the kill becomes `error` ("killing test X
  also fails with the method unchanged").
- each timeout, and each kill with no failing test named (exit, suite-level
  failure): the mutant's tests, with the mutant's deadline for a timeout. If
  that fails, `error`.
One warning per subject counts the overturned verdicts. Only checked
verdicts are stored for `--incremental`.

Why not a full neutral check before the mutants (the first design): it ran
every covering test of every subject. On human-essentials, two model
callbacks that every factory runs have ~850 covering tests each; the neutral
checks of `Item` took 286 s against 211 s for all 98 of its mutants. The
verdict check runs a handful of tests per subject and is stricter (it checks
the order each kill actually ran in, which reordering by prior killers had
already broken in the old design).

Timeouts no longer come from a neutral run: they come from the per-test
durations recorded while the map was built (with coverage on, so slower than
normal), times `timeout_factor`, at least `timeout_min`. A timeout that is
only the tests being slow is caught by the verdict check.

## 9. Integrations

One interface (`Saboteur::Integration::Base`): `setup`, `all_tests`,
`run(ids) -> RunResult(passed, failed_ids, runtime)`.
- rspec (Phase 1): ids are rspec example ids (`./spec/x_spec.rb[1:2:1]`).
  Spec files are loaded once in the parent; the child filters the already
  loaded world to the selected ids and runs it, reporting through a custom
  formatter, not stdout. Fail-fast after the first failure.
- Minitest: out of scope for v1 (maintainer decision, 2026-10-09). The
  adapter interface stays public for third-party frameworks. The
  [RSpec dependency measurement](minitest.md) lists what an adapter would touch.
- rails (Phase 4, opt-in): `eager_load!` after boot, ActiveRecord reconnect
  after fork, refuse to start unless `RAILS_ENV=test` and every configured DB
  host is local (localhost / 127.0.0.1 / ::1 / unix socket).
  Recipes for Sidekiq, WebMock, VCR in `docs/recipes/`.

## 10. Config, CLI, output

This section predates exit 4 (--max-duration budget), the --max-timeouts/
--max-errors quality gates and the pr/audit presets; the README documents
the current flags, exit codes and --agent mapping.

`config/saboteur.rb`, overridden by CLI flags:

```ruby
Saboteur.configure do |c|
  c.integration = "rspec"
  c.require = ["./config/environment"]   # boot files
  c.include = ["lib/**/*.rb", "app/**/*.rb"]
  c.exclude = ["lib/**/version.rb"]
  c.arid = ['\\A(puts|pp|p|print|warn)\\b', '\\blogger\\.']
  c.timeout_factor = 3
  c.timeout_min = 5
  c.jobs = 1
  c.ignore_file = "config/saboteur_ignore.rb"
  c.sources = ["builtin"]                # or "path.rb:ClassName" for external sources
  c.reeval = "nesting"                   # the default; "class_eval" is the alternative (see 6.1)
  c.max_memory_mb = 2048                 # growth cap per mutant process tree
  c.max_processes = 64                   # process cap per mutant tree
  c.coverage_timeout = 3600              # seconds for the coverage-map build
  c.coverage_parts = 1                   # parallel children for the coverage-map build (--coverage-parts N)
  c.baseline_timeout = 300               # seconds for each verdict-check run
  c.verbose = false                      # true = --verbose always on: boot-time output
                                         # filters (rspec load errors, #608) keep raw text
end
```

This is a sample, not the full key list. `saboteur help` prints every command,
option, config key and exit code.

CLI: `saboteur help` lists every command and flag.

Output:
- Terminal: counts per status, score, wall time, then a unified diff per survivor.
- HTML report (`html_report`) and per-method findings (`reporter/html.rb`, `reporter/findings.rb`).
- JSON: Stryker mutation-testing-report-schema (schemaVersion "2"). The
  `saboteur` object carries the run's peak-memory record (`memory`: per-worker
  `peakMb` and `supervisorPeakMb`) where the platform measured it (#202). Status
  mapping: killed->Killed, survived->Survived, timeout->Timeout,
  error->RuntimeError, resource_limit->RuntimeError (statusReason "resource limit: ..."),
  skipped->Ignored (reason in `statusReason`), no coverage
  ->NoCoverage.
- Ignore list (`config/saboteur_ignore.rb`): Ruby DSL entries
  `i.mutation "<digest>", subject:, reason:`; `reason`
  is required and the file fails to load without it. Stale entries (no
  matching mutation) are reported as warnings.

Exit codes (`saboteur help` is authoritative):
- 0: no unignored survivors and at most half of the executed mutants errored.
  With `--threshold`, 0 means the score is at or above it, even if mutants
  survived.
- 1: an unignored survivor. With `--threshold`, 1 means the score is below it
  or no mutant was tested, so there is no score.
- 2: usage or configuration error.
- 3: tool error: boot failure, a failed baseline, or more than half of the
  executed mutants errored. With `--threshold`, any errored or resource-limited
  mutant also exits 3, because the score is incomplete.
- `--agent` prints one JSON payload and maps its verdict to the same codes:
  clean 0, survivors 1, invalid invocation 2, incomplete or tool failure 3.

## 11. Extension point: mutation sources

`Saboteur::MutationSource::Base#mutations_for(subject)` yields `Mutation`
objects (subject id, operator name, edits, coarse flag, source name). The
built-in operators are one source. An external source (e.g. a service that
proposes edits) returns edits by file and byte range; saboteur validates that
every edit is inside the subject range, re-parses, de-duplicates by digest,
and runs it like any other mutant. No LLM source ships in v1.

## 12. Open questions

None open. Resolved: 6.1 uses the lexical-nesting wrapper by default
(maintainer decision M1). Resolved after review (see 14): post-start death is `error`; a coarse timeout
or error does not skip fine mutants.

## 12a. Code layout

```
lib/saboteur.rb                 requires; Saboteur.hook
lib/saboteur/cli.rb, config.rb, hooks.rb, ignore_list.rb, result.rb
lib/saboteur/subject.rb, subject_finder.rb      what can be mutated
lib/saboteur/mutation_source/   PUBLIC: Base, Edit, Mutation; Builtin operators
lib/saboteur/integration/       PUBLIC: Base; RSpec adapter
lib/saboteur/engine.rb          the pipeline
lib/saboteur/engine/            Boot, BaselineGuard, SubjectSelection, CoverageStore,
                                Candidates, CandidateSelection, DiffScope,
                                Distribution, Scheduler, ResultCache,
                                VerdictCheck, RunFingerprint, Diagnostics
lib/saboteur/execution/         Supervisor, ProcessTree, Protocol, Runner,
                                Reevaluator (everything that forks or evals)
lib/saboteur/selection/         CoverageMap, Recorder, GitDiff
lib/saboteur/frameworks/        Rails profile
lib/saboteur/reporter/          Terminal, Stryker, Diff, Html, Findings, Replay,
                                Agent (and its helpers)
```

Public API (stable across minor versions): `Saboteur::MutationSource::Base`,
`Edit`, `Mutation`; `Saboteur::Integration::Base`; `Saboteur.hook`; config
keys; CLI flags; the Stryker JSON report. Everything else may change.

## 13. Trade-offs summary

| choice | gain | cost |
|---|---|---|
| fork per mutant | full isolation, no state leaks, simple rollback | no Windows/JRuby; forking a big Rails app costs ~ms-tens of ms each (to measure) |
| byte-range edits | exact diffs, no unparser | operators must emit valid text; re-parse guards it |
| coverage per test | runs few tests per mutant | one slow instrumented suite run per cache key; before(:all) attribution |
| coarse first | early feedback and killer prioritization | fine mutants still run, so there is no survivor-gating time saving |
| method-level subjects only | simple, re-evaluable unit | misses class-body/DSL logic (validations, scopes) |

## 14. Second opinion (Grok CLI, 2026-10-06)

The design was reviewed by the Grok CLI. Accepted and folded in above:
- Build the coverage map in a forked child; never run tests in the parent (6, 7).
- Require executed examples == requested ids, else `error` (6.4).
- Magic comments are dropped by eval (verified by experiment); refinements are lost (6.1).
- Score formula contradicted "timeouts count as detected"; fixed (6.4).
- Post-start death -> `error`; `SystemExit` in tests -> killed via normal result (6.4).
- No equivalent coarse mutants; coarse timeout/error does not skip fine mutants (5).
- Fork hygiene: sockets, threads, Coverage/SimpleCov; reap the group on every exit (6, 6.3).
- Resolve owner constant before re-eval (Zeitwerk shadow classes) (6.1).
- Cache key includes resolved config (7).

Rejected, with reason:
- Cut `--since`, Stryker JSON, the hook set, and the mutation-source
  interface from v1: all four are explicit product requirements. They are
  scheduled after the core is proven (Phase 3), which addresses the "build on
  an untrusted core" concern.
- Lock jobs to 1: already the plan until Phase 5.
- Drop statement removal and literal mutations: part of the v1 operator set;
  Phase 2 measures their share of mutants and runtime before any cut.
- Prism offset mismatch between bundled 0.19 and the gem: saboteur only
  loads the prism gem (>= 1.2) and computes all offsets with it.

Noted as risks, not designed for yet: `before(:suite)` re-running in children
and `before(:all)` attribution (measure in Phase 1/2); `extend self`,
`private_class_method`, captured `Method` objects (list in limitations).
