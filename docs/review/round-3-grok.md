I'll verify A1–A10 against the code as it stands after those commits, read-only, and look for defects the specs miss.Round 2 amended A1, A3, A5, and A10. I'll check those rules in the current tree, then the rest of A1–A10.The tree moved while I was reading it: a result cache showed up in the scheduler. I'll re-read the files that A1–A10 depend on.**A1. Done-with-defect.** Catch-all `body_raise` is omitted (`builtin.rb:65-86`), and a coarse survivor skips fine mutants only when `Subject#recovers?` is false (`scheduler.rb:90-92`). `recovers?` (`subject.rb:89-91`) is true only for a `BeginNode` rescue or else on the method itself. A modifier rescue (`def m; work rescue 1; end`) and a `begin`/`rescue` nested under another statement stay invisible, so a coarse `body_nil` survivor still drops the fine mutant that rescue would expose. The spec uses a method-level `rescue` only (`scheduler_spec.rb:67-70`).

**A2. Done.** `nothing_to_remove?` (`builtin.rb:70-72`) requires every replaced statement to be arid, or a lone `nil`. `design.md:85-86` matches.

**A3. Done-with-defect.** `test/` is out, hook files and config `require` files are content-hashed, and the whole `.saboteur.yml` is not (`coverage_store.rb:13-60`). A file named only by `.rspec`, `.rspec-local`, or `rspec_args` `--require` and living outside `spec/` is still absent: only the options text is hashed. The spec covers those paths when they are the boot or hook file (`coverage_store_spec.rb:57-64`).

**A4. Done.** A neutral-check timeout is `baseline timeout`; every other non-pass is `baseline failure` (`scheduler.rb:70`).

**A5. Done-with-defect.** Re-alias runs only when `original_name` and `source_location` match, and that alias's visibility is restored (`reevaluator.rb:115-132`). A refused alias is never reported. `design.md:205-210` still says aliases keep the old body and should be reported.

**A6. Done.** A negative `proc_listallpids` raises; a full buffer doubles and retries without reading past it (`process_table.rb:76-84`). The spec locks a pid count (`process_table_spec.rb:62-83`).

**A7. Done.** The diff runs with `core.quotePath=false` and unquotes C-quoted paths (`git_diff.rb:19`, `47-53`). With that setting, git still octal-escapes only controls (values ≤ 127), so `to_i(8).chr` stays in range. Quotes, backslashes, spaces, and non-ASCII are spec'd (`git_diff_spec.rb:48-61`).

**A8. Done.** The example exception class is stored (`rspec.rb:125`, `runner.rb:143-144`). Named RSpec expectation errors become `"assertion"`; any other class is a crash kill (`runner.rb:155-158`, `result.rb:43-44`). `SystemExit` stays `"test called exit"` with no `kill_cause` (`runner.rb:137`), so it sits outside the crash share. The score formula is unchanged (`result.rb:87-92`).

**A9. Done.** `Diagnostics` has no `finish_progress`.

**A10. Done-with-defect.** `--since` keeps every coarse mutant and only fine edits that intersect the diff (`diff_scope.rb:16-28`). JSON lists every mutant (`stryker.rb:54-58`). The terminal shows one survivor per edit start line, coarse first, then lowest start byte (`terminal.rb:113-118`). An ignored coarse survivor wins the line and hides a live one. A multi-line edit occupies only its first line, so a second survivor lower in that span still prints. The spec is two live one-line mutants (`terminal_spec.rb:48-54`).

**New.** Opt-in `--incremental` (`result_cache.rb:72-87`, `engine.rb:12-13` and `68-72`) does not hash hook files, `spec/**` support files, or boot-file contents. The coverage key does (`coverage_store.rb:46-56`). The verdict fingerprint hashes the example file named in the test id. Editing `spec/support` can reuse a stale kill. The end-to-end spec edits the example file (`phase3_spec.rb:63-66`). The documented callee hole remains.

**Convergence.** Agreed and in the tree: A2, A4, A6, A7, A8, A9; A1's catch-all omission and the method-level rescue/else stop; A3's `spec/`-only key, hook hashing, and no whole-file config hash; A5's location guard and visibility restore; A10's coarse-per-method scope, fine mutants on changed lines, and a full JSON list. D1 (a skip is not a kill; Minitest stays out) and D2 (the parent-death watcher is negligible) stand. Open: the defects above; A11 dogfood triage; D3's block-def census; M1 default `nesting`, M2 the operator set, M3 `||=` memoization, M4 resource-limit status, M5 `--strict`. Round-2 scores assumed these amendments were finished, so they do not move.
