# saboteur design

Status: draft for v1. Sections marked OPEN need a decision before Phase 1 code.

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
mutants would only add noise.

Fine:
- Comparison: `>=`<->`>`, `<=`<->`<`, `==`<->`!=`, `<`<->`>`, `<=`<->`>=`.
- Boolean: `&&`<->`||` (and `and`/`or`), drop `!`/`not`, condition -> `true`,
  condition -> `false` (for `if`/`unless`/`while`/`until`/ternary predicates).
- Arithmetic: `+`<->`-`, `*`<->`/`, integer/float literal n -> n+1, n-1, 0
  (skip the replacement equal to n).
- Statement removal: each statement of the body, one at a time (not the last
  statement when the body has one statement; coarse covers that).
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

Child:
1. `Process.setpgid(0, 0)` so the child and anything it spawns share a group.
2. `after_fork` (DB reconnect etc.).
3. Re-evaluate the mutated method (see 6.1), restore visibility (6.2).
4. Write `started` to the result pipe.
5. `around_mutant { adapter.run(test_ids) }`.
6. Write result to the pipe, `exit!` (skip at_exit handlers of the target).

Mutated source is never written to disk in the target project.

### 6.1 Re-evaluation — OPEN

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

Decision needed: adopt the wrapper, or keep `owner.class_eval` and accept the
skip rate. Phase 1 will measure the skip rate both ways on the fixtures.

### 6.2 Visibility

Re-defining a method with `def` makes it public (measured: a private method
became public after `class_eval`). Before re-evaluation, record
`private_method_defined?` / `protected_method_defined?` on the owner (singleton
class for `def self.x`) and re-apply `private`/`protected` after. Also handles
`private def x`, `private :x`, and `private` sections.

Known gaps (documented, not fixed in v1):
- `module_function`: the module-level copy is a separate method; mutating the
  instance method does not change `Mod.x`. Detect and re-apply `module_function`.
- `alias`/`alias_method` copies keep the old body. Callers through the alias
  see the original; such mutants may survive spuriously. Report the alias in
  the survivor output.
- Methods replaced at runtime (prepended modules, `Module#prepend` wrappers)
  still work: we redefine on the original owner and the prepend chain calls it.

### 6.3 Timeouts and process groups

- Per mutant: `max(3 x baseline_runtime(subject), 5 s)`; factor configurable.
- Parent waits on the result pipe with that deadline. On timeout:
  `Process.kill("TERM", -pgid)`, wait 1 s, `Process.kill("KILL", -pgid)`, reap.
  This also kills grandchildren (spawned servers, subprocesses).
- Parent also reaps on its own exit (at_exit + trap INT/TERM) so Ctrl-C leaves
  no orphans.
- Caveat: a child that calls `setsid`/`setpgid` itself escapes the group. Rare
  in test code; documented.

### 6.4 Statuses

| status    | meaning                                                         |
|-----------|-----------------------------------------------------------------|
| killed    | `started` received and at least one selected test failed         |
| survived  | `started` received and all selected tests passed                 |
| timeout   | deadline passed; group killed                                    |
| error     | child exited/crashed before writing `started`, or adapter itself raised |
| skipped   | not run: baseline failure, no covering tests, or coarse survivor |

`error` is never counted as killed. Skips carry a reason. A child that
crashes (segfault, `exit!`) after `started` but before writing a result counts
as killed, since a test run that ends the process is detected behaviour: OPEN,
see 11.

Mutation score = killed / (killed + survived + timeout). Timeouts count as
detected (Stryker convention), shown separately.

## 7. Test selection: coverage map

- Coverage is started in `lines` mode before boot. After boot and test
  loading, `Coverage.result(stop: false, clear: true)` drops load-time counts.
- The parent runs the full suite once, test by test, calling
  `Coverage.result(stop: false, clear: true)` after each test; every line with
  a count > 0 maps to that test id.
- A subject's tests = union over the body lines of its `def` (excluding the
  `def` line for multi-line methods, since that line runs at load time; single
  line and endless defs use the def line, which only executes when called after
  the clear).
- Tests that run code in `before(:all)` / `before(:suite)` attribute that code
  to whichever test ran first. Mitigation: lines hit outside any test are
  recorded as "suite-level" and their subjects run the full test file list of
  the group. Measured impact pending (Phase 2).
- Cache: `.saboteur/coverage-<sha256>.json` keyed by the hash of every
  included source file, every test file, the lockfile and the saboteur
  version. Any change rebuilds. (Per-file incremental update is a later
  optimisation.)
- No covering tests -> subject skipped ("no coverage"), reported, not a survivor.

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
- minitest (Phase 3).
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
sources: [builtin]                 # external mutation sources by class name
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

1. 6.1: lexical-nesting wrapper vs spec'd `owner.class_eval`.
2. 6.4: child dies after `started` without a result. Proposed: killed (the
   mutation made the test process die). Alternative: error.
3. Coarse survivor -> skip fine mutants: also apply when the coarse mutant
   times out? Proposed: no, timeout means detected.

## 13. Trade-offs summary

| choice | gain | cost |
|---|---|---|
| fork per mutant | full isolation, no state leaks, simple rollback | no Windows/JRuby; forking a big Rails app costs ~ms-tens of ms each (to measure) |
| byte-range edits | exact diffs, no unparser | operators must emit valid text; re-parse guards it |
| coverage per test | runs few tests per mutant | one slow instrumented suite run per cache key; before(:all) attribution |
| coarse first | fast signal, fewer noisy survivors | a coarse survivor hides fine-grained detail until fixed |
| method-level subjects only | simple, re-evaluable unit | misses class-body/DSL logic (validations, scopes) |
