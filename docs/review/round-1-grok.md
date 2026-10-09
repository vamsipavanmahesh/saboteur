I'll read the design, status, survey, and validation docs first, then the engine, execution, selection, and specs, and judge the gem against those constraints only.Docs are in. Next I’ll read the engine, execution, selection, and mutation sources against the specs so the verdict is grounded in the code.**No.** This is a strong, measured v1 of the right architecture. It is behind the best open practice on operator quality, diff-scoped reporting, incremental reuse, parallelism, and any evidence past two small gems.

## 1. Scores

**Ruby mutation testing today: 5/10.** [code] Byte-range edits, one `def` per child, line-level test selection, coarse-first, neutral check, and process-tree containment are in place and match the design. [doc] Proof is dry-inflector and tty-color only; Rails (Mastodon) has not been run; `jobs` stays 1. The Ruby incumbent was not compared, by the clean-room rule.

**Signal-to-noise of survivors: 6/10.** [doc] On nesting runs, 31 survivors split 19 real gaps / 12 equivalent / 0 tool noise (about 39% equivalent, ordinary next to Schuler and Zeller's ~45%). Nine of the dry-inflector calls were by reading, not by running the mutant. [code] The score ignores skips, and the default reeval skips most mutants on nested constants, so the headline number describes the mutants that managed to run.

**Resource efficiency: 6/10.** [doc] After line selection, dry-inflector was 261 mutants in 19.8 s (0.046 s mean) at a peak of 4 processes and 176 MB. [code] Selection is per edit, prior killers then fastest, fail-fast. [inference] That is a good constant factor. Wall-clock state of the art on a real app also needs parallel workers and an opt-in result cache, which are absent, and fork-per-mutant cost on Rails is unmeasured.

## 2. Would a principal be impressed?

**Yes, by the engineer. No, as a ship decision.**

What stands out:

- [doc] Decisions are tied to measurements: `class_eval` skip rates 3.8% and 80.1% versus 0% for `nesting`; containment after a real fork-bomb; process-table read 58.8 ms to 7.9 ms; macOS `RLIMIT_AS` not enforceable, `RLIMIT_CPU` is.
- [code] False survivors are treated as a product bug. A child that runs a different example set than requested is `error` (`lib/saboteur/execution/runner.rb:137`). Unreached edits are `NoCoverage`, not survivors (`lib/saboteur/reporter/stryker.rb:87`).
- [code] Containment assumes descendants call `setsid`, tracks pid plus start time, stop-then-kill, and bounds recursion with `SABOTEUR_CHILD` (`lib/saboteur/execution/supervisor.rb:25`). That is someone who was burned and then read the kernel.
- [doc] Phase 2 names survivors one by one. The survey marks what was not re-read.

What would make them stop:

- [code] `reeval` still defaults to `class_eval` (`lib/saboteur/config.rb:29`) after their own numbers say `nesting` is strictly better. The open question is already answered.
- [doc] 165 dogfood survivors at `47b8bc8`, listed and not triaged. The tool's own suite is the unfinished demo.
- [doc] No run larger than 1138 examples. Confident docs, thin corpus.

## 3. Gaps, ranked

The survey's top two items (per-line selection, killer-then-fastest order) are already in the tree. [code] `lib/saboteur/engine/scheduler.rb:19` and `:89`. The note is stale on that point.

1. **Sufficient comparisons and booleans, plus predicate coarse mutants.** [code] Today `<` becomes `>` and `<=`, and `&&` only swaps with `||` (`lib/saboteur/mutation_source/builtin.rb:19`). [doc] Just 2012: the swap is subsumed; Descartes and cargo-mutants use typed body defaults. `body -> nil` misses "tests only check the false side" of a predicate. **Impact:** high on survivor quality. **Cost:** low, `Builtin` only; digests change. **Conflicts:** no. **Done when:** on both pinned gems, mutant count and the real/equivalent/noise table are re-measured; a fixture whose specs only assert the false branch survives `body -> true`; `<` to `>` is no longer emitted.

2. **Generation-time equivalence rules.** [doc] 12 of 31 survivors were equivalent; tty-color `Mode#mode` was a dead store mutated three ways; Google's early wins were logging, time, and config flags. [code] `@x ||=` still becomes `@x =` (`builtin.rb:108`). **Impact:** high, because noise is what developers see. **Cost:** low per rule, each with a fixture. **Conflicts:** no. Unsound rules must be listed. **Done when:** the `Mode#mode` literal mutants and an `@x ||=` memoization fixture are not emitted, and the equivalent share on the two gems drops.

3. **Coarse `raise` absorbed by `rescue` skips every fine mutant.** [code] Body replacement rewrites only the try statements (`builtin.rb:60`, spec locks this at `spec/saboteur/mutation_source/builtin_spec.rb:31`). Any coarse survivor drops the fine set (`scheduler.rb:67`). [inference] `def m; work; rescue; 1; end` with `expect(m).to eq(1)` kills `body_nil` and survives `body_raise`, so mutants of `work` never run. **Impact:** high on Ruby. **Cost:** low. **Conflicts:** no. **Done when:** a fixture with that shape still runs fine mutants of `work`, and a `body_raise` that rescue swallows is not a coarse stop.

4. **Review-shaped diff mode.** [code] `--since` keeps every mutant of a method that touches the diff (`lib/saboteur/engine/subject_selection.rb:44`). [doc] Google: median 7 mutants per change, and most mutants on one line share a fate. **Impact:** high for whether anyone uses it. **Cost:** low. **Conflicts:** no. Coarse mutants can stay per method. **Done when:** a one-line edit inside a long method emits coarse mutants plus only fine edits that intersect the diff; the terminal shows at most one survivor per line; the JSON report still lists them all.

5. **Opt-in result cache.** [doc] PIT and Stryker reuse kills when the killing test is unchanged, and they document the callee hole. **Impact:** high on CI wall time. **Cost:** medium. **Conflicts:** no. **Done when:** a second run with unchanged sources, tests, and lockfile forks no mutant child and returns the same statuses; editing the killer's file re-runs that mutant; `--no-cache` forces a full run.

6. **Parallel workers.** [doc] Phase 5, maintainer-gated. **Impact:** largest CPU lever, near-linear until cores or the database. **Cost:** medium for gems, high for Rails (one database per worker). **Conflicts:** no. Fork-per-mutant is what makes it possible. **Done when:** `jobs=N` on dry-inflector matches `jobs=1` statuses, wall time drops, and the watchdog reports no leftovers.

7. **Separate crash-kills from assertion-kills.** [code] `+` becomes `-` unless the operand is a literal string, array, hash, or symbol (`builtin.rb:127`), so variable operands die by `TypeError` and count as killed. [doc] The dynamic-language failure mode. **Impact:** medium, it stops the score from lying. **Cost:** low. **Conflicts:** no. **Done when:** each kill stores the failure class, and both pinned gems report the share of kills that are `NoMethodError`, `TypeError`, or `NameError`, per operator.

8. **`def` inside blocks.** [code] `SubjectFinder` does not walk blocks (`lib/saboteur/subject_finder.rb:39`), so `included do; def bar` is invisible. `define_method` and class-body DSL (validations, scopes) are outside the model. **Impact:** high on Rails, which is why Phase 4 matters. **Cost:** medium for lexical `def`s in blocks; high for `define_method`. **Conflicts:** block `def`s do not conflict with "one def per subject." `define_method` does conflict with def-only re-eval. **Done when:** a module that defines `def` inside `included` is mutated and the neutral check passes; `define_method` stays reported as unsupported.

Lower, and not ahead of a Mastodon run: sampling (`--sample N`, coarse always runs); an iseq compare dropped unless it removes at least 1% of mutants on the two gems; HTML via mutation-testing-elements; LLM triage only as an opt-in that never sends source unless asked. Schemata, in-process swap, and fork-at-first-call conflict with fork-per-mutant isolation. Leave them.

## 4. Wrong, risky, or extra

- **Wrong default.** [code] `lib/saboteur/config.rb:29` ships `class_eval`. [doc] That skipped 80.1% of tty-color and 3.8% of dry-inflector; `nesting` skipped 0% for that reason. The score then describes the remainder (`lib/saboteur/result.rb:73`).
- **Wrong coarse stop.** [code] `builtin.rb:59` plus `scheduler.rb:67`, as in gap 3. The "no equivalent coarse mutants" rule does not know about `rescue`.
- **`body_nil` dropped when the last line is arid.** [code] `builtin.rb:63`. A method that does real work and then `puts` or `logger.info` never gets the mutant that means "called, result unchecked." `body_raise` is killed by the call itself. The spec locks this in (`builtin_spec.rb:26`).
- **Minitest skips count as passes.** [code] `lib/saboteur/integration/minitest.rb:70` (`passed? || skipped?`). A covering test that `skip`s lets the mutant survive, and the neutral check passes too.
- **Neutral-check timeout is labeled "baseline failure."** [code] `scheduler.rb:42` and `:55`. A slow subject and a constant-resolution failure look the same in the report. The warning text has the real status; the mutant rows do not.
- **Stale coverage map.** [code] The key hashes test files and the lockfile (`lib/saboteur/engine/coverage_store.rb:13`, `:36`), but `require` entries are paths, not contents, and RSpec's file list is example files only (`lib/saboteur/integration/rspec.rb:31`). Editing `spec_helper` or a support file does not rebuild the map, so later runs select the wrong tests.
- **Aliases keep the old body.** [code] Restore handles visibility and `module_function` only (`lib/saboteur/execution/reevaluator.rb:108`). [doc] Design 6.2 says to report the alias on the survivor. Callers through `alias_method` never see the mutant, so it survives.
- **Partial harness failure is a green run.** [code] `lib/saboteur/cli.rb:74` exits 3 only when every executed mutant errored. Killed plus `error` and no survivor exits 0.
- **Resource-limit death counts as a detected kill.** [code] `runner.rb:99` maps memory and process caps to `timeout`, and timeouts raise the score. An out-of-memory mutant improves the number.
- **Risky: parent-death thread.** [code] `supervisor.rb:127` starts a thread in every child. A test that later `fork`s can deadlock on a lock that thread holds. `spawn` is fine.
- **Risky: libproc layout.** [code] Offsets are hardcoded (`lib/saboteur/execution/process_table.rb:38`). The spec checks ppid and pgid against `ps` on the current OS, so today's machines are covered. A layout change silently tracks the wrong processes. `proc_listallpids` (`process_table.rb:68`) does not retry when the count exceeds 16384; a negative return is also unchecked.
- **Risky: git paths.** [code] `lib/saboteur/selection/git_diff.rb:27` strips `b/` and does not unquote. A path git quotes (`"b/my file.rb"`) is missed, so `--since` drops that file.
- **Over-broad, safe.** [code] Any `using` skips every subject in the file (`subject_finder.rb:86`).
- **Not over-engineered.** [code] The engine split is a short pipeline (`lib/saboteur/engine.rb` is wiring). Containment is large because a process group was not enough. The extra piece that does not earn its keep is keeping `class_eval` as a peer strategy after the measurement. `Diagnostics#finish_progress` (`lib/saboteur/engine/diagnostics.rb:36`) is never called.

I did not run the suite. Line cites are from reading the tree.
