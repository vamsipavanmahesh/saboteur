# saboteur design

Status: v1 as built (2026-10-09). Sections marked OPEN wait for a maintainer
decision; docs/status.md tracks them.

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
  -> load tests via integration adapter
  -> coverage map (cached)                 file:line -> [test ids]
  -> subject finder (Prism)                def bodies in included files
  -> [--since] filter subjects by git diff
  -> per subject:
       baseline: fork, re-eval UNCHANGED, run selected tests, time it
         fail -> skipped (baseline failure)
       coarse mutants (body -> nil, body -> raise)
         any survives -> report it, skip fine mutants for this subject
       fine mutants
         each: fork -> re-eval mutated def -> run selected tests -> status
  -> reporters: terminal, Stryker JSON; ignore list applied; exit code
```

## 3. Parsing and subjects

- Prism parses each included file. Ruby 3.3 bundles prism 0.19, whose API
  predates 1.0, so the gemspec depends on the prism gem `>= 1.0, < 2`.
- Subject = one `DefNode`: instance methods and `def self.x`. Methods inside
  `class << self` count as singleton methods of the enclosing class.
- Subject id: `Outer::Klass#meth` or `Outer::Klass.meth`, from the lexical
  nesting Prism reports (ModuleNode / ClassNode / SingletonClassNode chain).
- Skipped in v1: `define_method`, DSL calls in a class body, constants, code
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

Coarse (run first per subject):
- body -> `nil`
- body -> `raise`

If either survives, report it and skip fine mutants for the subject: a method
whose whole body can be deleted unnoticed has no meaningful test, and the fine
mutants would only add noise. Only `survived` triggers the skip; timeout or
error on a coarse mutant does not.

Equivalent coarse mutants are not generated: no `body -> nil` for a body that
is empty, a lone `nil`, or only arid statements (logging); no `body -> raise`
when the method's own rescue catches `StandardError` (the raise is what the
rescue is for). A surviving coarse mutant stops the fine mutants, except in
a method with `rescue` or `else`, which can return a value of its own.

Fine:
- Comparison (sufficient set, Kaminski et al. 2011): `<` -> `<=`, `!=`,
  `false`; `<=` -> `<`, `==`, `true`; `>` -> `>=`, `!=`, `false`;
  `>=` -> `>`, `==`, `true`; `==` -> `false`, `true`; `!=` -> `true`,
  `false` (not `<=`/`>=`: they raise on non-Comparable objects).
- Boolean (sufficient set, Just et al. 2012): `a && b` -> `a`, `b`,
  `false`; `a || b` -> `a`, `b`, `true` (same for `and`/`or`); drop
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
- Before each fork the parent holds no open DB/Redis sockets: Rails
  integration disconnects pools after boot; `before_fork` is the hook for
  anything else. The child opens fresh connections in `after_fork`.
- Threads do not survive fork, and a mutex held by another thread stays
  locked in the child. The parent must be effectively single-threaded at fork
  time; saboteur warns when `Thread.list.size > 1` before the first fork.

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
- Refinements (`using`) are lexical and are lost. Subjects in files that call
  `using` are skipped in v1 ("refinements").

Both are implemented (`reeval: nesting | class_eval`). Default: `nesting`
(maintainer decision M1, 2026-10-09). Measured skip rate from the lost
lexical scope (neutral check fails): 3.8 % of mutants on dry-inflector and
80.1 % on tty-color with `class_eval`, 0 % with `nesting`
(docs/validation/phase-2-gems.md). Recommendation: `nesting`.

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

`Execution::Supervisor` enforces the invariant for mutants, neutral checks
and the coverage-map child alike:

- Tracks the whole descendant tree (`Execution::ProcessTree`) by parent link
  and by the child's process group, rebuilt from the process table on every
  poll, remembering every pid ever seen (pid + start time, so a recycled pid
  is never signalled).
- After every child, whatever its outcome: SIGSTOP every member until no new
  member appears (a stopped process cannot fork), then SIGKILL them all.
  Survivors of a normal exit are reported as leftovers (a warning).
- While the child runs: a deadline (per mutant `max(3 x neutral-check
  runtime, 5 s)`), a cap on memory growth across the tree (default 2 GB) and
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
| skipped   | not run: baseline failure, no covering tests, or coarse survivor |

`error` is never counted as killed. Skips carry a reason. A child that dies
after `started` without writing a result is `error`: from outside, a crash in
the harness looks the same as one caused by the mutation. The child rescues
`SystemExit` from test code and reports it as a normal failed run, so
`exit` inside a test still counts as killed.

A run where the adapter executed a different set of examples than requested
(count or ids differ) is `error`, never survived. This guards against a broken
filter turning every mutant into a false survivor.

Mutation score = (killed + timeout) / (killed + survived + timeout). Timeouts
count as detected (Stryker convention) and are shown separately. Errors and
skips are outside the score and always shown, so a harness problem cannot
raise the score silently.

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
- A subject's tests (used by its neutral check and its coarse mutants) =
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
  terminal shows one survivor per line (live before ignored, then coarse,
  then the earliest edit);
  the JSON report keeps all.
- Incremental mode (`--incremental`, opt-in): a stored verdict (killed,
  survived, timeout) is reused while the method source, the mutant, the set
  of covering tests, their files' contents, the lockfile, the verdict-
  relevant config and the saboteur version are unchanged. When every verdict
  of a method is reusable, nothing forks, not even the neutral check. Hole:
  changes in callees are invisible (as in PIT), hence opt-in.
- Order: tests that killed earlier mutants of the same subject first, then
  fastest first (suite order breaks ties). With fail-fast, a mutant is killed
  by its cheapest killing test. Mutants always run a subsequence of the order
  the neutral check validated.
- Cache: `.saboteur/coverage-<sha256>.json` keyed by the hash of every
  included source file, every test file, the lockfile, the resolved config
  (boot files, integration) and the saboteur version. Any change rebuilds.
  (Per-file incremental update is a later optimisation.)
- No covering tests for a subject -> all its mutants "no coverage".

Trade-off: test-by-test coverage collection costs one full suite run with
coverage on (typically 1.2-2x slower than normal; to be measured), paid once
per cache key.

## 8. Neutral check

Before mutating a subject: fork, re-evaluate the UNCHANGED method text the
same way mutants are evaluated, restore visibility, run the selected tests.
- Fails -> subject `skipped: baseline failure`, no mutants run.
- Passes -> its wall time is the subject's baseline for the timeout.

This validates the re-eval path itself (6.1) and catches order-dependent or
flaky tests before they produce false "killed" results.

## 9. Integrations

One interface (`Saboteur::Integration::Base`): `setup`, `all_tests`,
`run(ids) -> RunResult(passed, failed_ids, runtime)`.
- rspec (Phase 1): ids are rspec example ids (`./spec/x_spec.rb[1:2:1]`).
  Spec files are loaded once in the parent; the child filters the already
  loaded world to the selected ids and runs it, reporting through a custom
  formatter, not stdout. Fail-fast after the first failure.
- Minitest: out of scope for v1 (maintainer decision, 2026-10-09). The
  adapter interface stays public for third-party frameworks.
- rails (Phase 4, opt-in): `eager_load!` after boot, ActiveRecord reconnect
  after fork, refuse to start unless `RAILS_ENV=test` and every configured DB
  host is local (localhost / 127.0.0.1 / ::1 / unix socket).
  Recipes for Sidekiq, WebMock, VCR in `docs/recipes/`.

## 10. Config, CLI, output

`.saboteur.yml`, overridden by CLI flags:

```yaml
integration: rspec
require: [./config/environment]   # boot files
include: [lib/**/*.rb, app/**/*.rb]
exclude: [lib/**/version.rb]
arid: ['\A(puts|pp|p|print|warn)\b', '\blogger\.']
timeout_factor: 3
timeout_min: 5
jobs: 1
ignore_file: .saboteur-ignore.yml
sources: [builtin]                 # or path.rb:ClassName for external sources
reeval: class_eval                 # or nesting (see 6.1)
max_memory_mb: 2048                # growth cap per mutant process tree
max_processes: 64                  # process cap per mutant tree
coverage_timeout: 3600             # seconds for the coverage-map build
baseline_timeout: 300              # seconds for each neutral check
```

CLI: `saboteur run [--since REF] [--subject 'Klass#meth'] [--timeout-factor N] [--jobs N]`.

Output:
- Terminal: counts per status, score, wall time, then a unified diff per survivor.
- JSON: Stryker mutation-testing-report-schema (schemaVersion "2"). Status
  mapping: killed->Killed, survived->Survived, timeout->Timeout,
  error->RuntimeError, skipped->Ignored (reason in `statusReason`), no coverage
  ->NoCoverage.
- Ignore list: YAML entries `{subject, mutation (digest), reason}`; `reason`
  is required and the file fails to load without it. Stale entries (no
  matching mutation) are reported as warnings.

Exit codes: 0 no unignored survivors; 1 unignored survivors; 2 usage/config
error; 3 tool error (boot failed, all subjects errored).

## 11. Extension point: mutation sources

`Saboteur::MutationSource::Base#mutations_for(subject)` yields `Mutation`
objects (subject id, operator name, edits, coarse flag, source name). The
built-in operators are one source. An external source (e.g. a service that
proposes edits) returns edits by file and byte range; saboteur validates that
every edit is inside the subject range, re-parses, de-duplicates by digest,
and runs it like any other mutant. No LLM source ships in v1.

## 12. Open questions

1. 6.1: lexical-nesting wrapper (with magic comments, owner pre-resolution)
   vs spec'd `owner.class_eval`. Recommended: wrapper.

Resolved after review (see 14): post-start death is `error`; a coarse timeout
or error does not skip fine mutants.

## 12a. Code layout

```
lib/saboteur.rb                 requires; Saboteur.hook
lib/saboteur/cli.rb, config.rb, hooks.rb, ignore_list.rb, result.rb
lib/saboteur/subject.rb, subject_finder.rb      what can be mutated
lib/saboteur/mutation_source/   PUBLIC: Base, Edit, Mutation; Builtin operators
lib/saboteur/integration/       PUBLIC: Base; RSpec adapter
lib/saboteur/engine.rb          the pipeline
lib/saboteur/engine/            Boot, SubjectSelection, CoverageStore,
                                Candidates, Scheduler, Diagnostics
lib/saboteur/execution/         Supervisor, ProcessTree, Protocol, Runner,
                                Reevaluator (everything that forks or evals)
lib/saboteur/selection/         CoverageMap, Recorder, GitDiff
lib/saboteur/frameworks/        Rails profile
lib/saboteur/reporter/          Terminal, Stryker, Diff
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
| coarse first | fast signal, fewer noisy survivors | a coarse survivor hides fine-grained detail until fixed |
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
  loads the prism gem (>= 1.0) and computes all offsets with it.

Noted as risks, not designed for yet: `before(:suite)` re-running in children
and `before(:all)` attribution (measure in Phase 1/2); `extend self`,
`private_class_method`, captured `Method` objects (list in limitations).
