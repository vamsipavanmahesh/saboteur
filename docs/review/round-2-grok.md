I'll verify Claude's A/M/D points against the tree before answering, starting with the disputed ones.**A1. Contest: dropping `body_raise` is necessary, and it is not sufficient.** [code] `builtin.rb:65-86` and `builtin_spec.rb:35-51` already omit `body_raise` for a bare rescue, `StandardError`, or `Exception`, and `body_nil` still rewrites only the try statements. [code] `scheduler.rb:67` still drops every fine mutant when any coarse mutant survives. Fixture: `def m; work; rescue; 1; end` with `assert_nil m`. If `work` returns nil, `body_nil` survives, while a fine mutant that makes `work` raise returns 1 and would fail. It never runs. [doc] design.md:80-83 assumes a deletable body means the fine mutants are noise. That is false when `rescue` or `else` returns another value. A coarse survivor may suppress fine mutants only when the method has no `rescue` and no `else`.

**A2. Accept.** [code] `nothing_to_remove?` (`builtin.rb:69-72`) requires the whole body to be arid; `builtin_spec.rb:31-32` locks work-then-`puts`. [doc] design.md:86 still says the last statement. Update that sentence.

**A3. Accept the key, with two holes.** [code] `coverage_store.rb:13-58` and `coverage_map.rb:72-77` hash `spec/**/*.rb`, config `require` contents, `.rspec`, `.rspec-local`, and the lockfiles. Leave `test/**/*.rb` out. [doc] Minitest is dropped (`status.md:66`). [code] A file named only by `.rspec --require` and living outside `spec/` is not content-hashed, and hook files are absent from `CACHE_INPUTS`. Hash those. Hashing all of `.saboteur.yml` duplicates the extra digest.

**A4. Accept.** [code] `scheduler.rb:42` and `:55-60` store `baseline failure` for every non-pass, including a timeout. Split `baseline timeout` from `baseline failure`.

**A5. Accept re-pointing, with a guard.** [doc] design.md:205-207 only asks to report the alias. [code] `reevaluator.rb:108-114` restores visibility and `module_function` only. `Method#original_name` still names the old method after that method is redefined, so a stale alias would move and the neutral check would change a different method. Re-alias only when the alias and the subject share `source_location`, and restore the alias's visibility. Otherwise report `alias`.

**A6. Accept.** [code] `process_table.rb:68-71` slices `4 * count` unchecked. A negative return is a failure. If `count > LISTALL_LIMIT`, do not read past the buffer; grow and retry. [code] `process_table_spec.rb:36-40` only checks ppid and pgid against `ps`, so a change of return unit would look like a wrong tree.

**A7. Accept.** [code] `git_diff.rb:26-28` strips `b/` and does not unquote. Pass `-c core.quotePath=false` on the git command. [doc] git-config: `quotePath=false` stops quoting bytes ≥ 0x80; `"`, `\`, and bytes < 0x20 stay quoted, so unquote those. A space is not quoted.

**A8. Accept.** [code] `runner.rb:130-134` stores failed ids and no exception class. Record `notification.exception.class` from `rspec.rb:121`. Keep `SystemExit` as the existing exit-kill (`runner.rb:128`), outside the crash-kill share. Do not change the score in this item.

**A9. Accept.** [code] `Diagnostics#finish_progress` is already gone.

**A10. Accept.** [code] `--since` keeps every mutant of a method that touches the diff (`subject_selection.rb:44-49`). The terminal prints every survivor (`terminal.rb:70`). Coarse per changed method, fine only where an edit intersects the diff, one terminal survivor per line, full list in JSON. Choose the shown one by coarse first, then lowest start byte.

**A11. Accept.** I did not re-count 148 or those commits. [doc] `status.md:45` still says 165 at `47b8bc8`. Update it with the new count.

**M1–M5. Accept: the maintainer decides.** Recommendations, so the scores have a premise. M1: default `nesting`. [doc] phase-2-gems.md: `class_eval` skips 3.8% and 80.1%, `nesting` skips 0% for that reason. M2: adopt the sufficient comparison set, `&&`/`||` operand replacement, and predicate `body -> true/false`, then re-measure. The brief's operator list is why this is not unilateral. M3: skip `@x ||=` memoization only as a listed, unsound rule. M4: memory and process caps get their own status and stay out of the score. Deadline timeouts stay detected. [doc] design.md:253 and :267. M5: keep exit 0/1 as specified (`cli.rb:75-79`, design.md:370). Add `--strict` and an stderr line, `incomplete run: N errors`.

**D1. Semantics accepted. Do not pin a Minitest spec.** [doc] Minitest is out of scope (`status.md:66`, design.md:329). [code] `minitest.rb` is gone, and `integration_spec.rb:5-8` locks a single adapter. RSpec already treats skip as not-killed: only `example_failed` fills `failed` (`rspec.rb:120-122`). [inference] A `skip if` the mutant turns on is a false survivor of the same kind as an early return.

**D2. Accept.** [code] The watcher (`supervisor.rb:127-133`) only sleeps and reads `Process.ppid`. It takes no `Mutex`. The lock I meant was MRI's per-thread `interrupt_lock` inside `native_sleep`. On Ruby 3.x, `rb_thread_atfork_before_fork` acquires those locks before `fork`, and the child keeps only the forking thread. MRI already has a timer thread, and the parent warns when another thread is alive (`engine.rb:54-58`, design.md:120-122). A grandchild has no watcher. `ProcessTree` and `RLIMIT_CPU` still cover it (design 6.3). Negligible on 3.3.

**D3. Defer the implementation. Contest the measurement.** [code] `SubjectFinder#walk` returns on `BlockNode` (`subject_finder.rb:39-40`), so a Mastodon run counts none of these defs. An `included` block defines the method on the including class. The module is the wrong owner (`scheduler.rb:101-109`). Parse-census three buckets: `included` / `class_eval` blocks, `Class.new` blocks, and `define_method` (still unsupported). Decide from that count.

## Scores

These assume A1–A11 as amended, M1 and M4 accepted, and M2–M3 either accepted (first number) or declined (second).

**Ruby mutation testing: 7/10, or 6/10 without M2.** [inference] The footguns in this review are closed and diff mode exists. There is still no result cache and `jobs` stays 1, so it is behind PIT, Stryker, and mutmut on repeat runs and on CPU.

**Signal-to-noise: 7/10 with M2 and M3, else 6/10.** [doc] 12 of 31 nesting survivors were equivalent. Reclassify both gems after the operator change before using 7.

**Resource efficiency: 6/10 either way.** [doc] Line selection is already the constant-factor win (dry-inflector 19.8 s). A10 cuts review runs. Wall-clock state of the art is the cache or `jobs`.

If the maintainer keeps `class_eval` as the default, do not use the 7. That default still skips 80.1% of tty-color, and the score describes whoever got past the neutral check.

## Minimum evidence

For **Ruby gems**: `nesting` is the default; an M2 before/after table on both pinned gems (mutant count, score, real/equivalent/noise); the A8 crash-kill share per operator; one opt-in cache demo on dry-inflector (a second unchanged run forks no mutant child and returns the same statuses; editing the killer's file re-runs that mutant).

For **Ruby including apps**: the gem bar, plus Mastodon at the pinned commit, `jobs=1`, under the watchdog: subjects, status counts, wall time, peak RSS and processes, leftover count, a hand classification of at least 30 survivors (or all of them), and the block-def census. `jobs=N` can stay unbuilt if the report says each worker needs its own database.

I would not ask for HTML, an iseq pass, schemata, or LLM triage before using "state of the art."
