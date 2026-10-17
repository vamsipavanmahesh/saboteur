# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivors accepted with a reason. Each digest is printed next to its survivor.
Saboteur.ignore do |i|
  i.mutation "9339724fc1dce5eb",
             subject: "Saboteur::SubjectFinder#heredoc_eval?",
             reason: "equivalent on admitted inputs: the immediately preceding arguments&.size == 1 guard establishes a one-element Array, so first and last agree - not a general first/last equivalence"

  i.mutation "7f27bf4227807c2c",
             subject: "Saboteur::SubjectFinder#heredoc_eval?",
             reason: "equivalent conditional on the Prism 1.9.0 AST contract: an admitted node's Location slice is always a String, so &. and . agree - not extended to hand-built nodes"

  i.mutation "05859430e8066ebc",
             subject: "Saboteur::SubjectFinder#heredoc_eval?",
             reason: "equivalent conditional on the Prism 1.9.0 AST contract: no admitted direct-argument StringNode has nil opening_loc (nil openers exist only on container parts), so &. and . agree - not extended to hand-built nodes"

  i.mutation "751004d184cd7c5b",
             subject: "Saboteur::SubjectFinder#heredoc_eval?",
             reason: "equivalent conditional on the Prism 1.9.0 AST contract: slice starts at the node's first byte, so slice and opening_loc&.slice give the same start_with?(<<) verdict - this is not the killed &.slice removal"

  i.mutation "4121be32fbbef2b5",
             subject: "Saboteur::SubjectFinder#walk_heredoc_eval",
             reason: "equivalent on the production call path: walk_heredoc_eval is entered only after heredoc_eval? admitted exactly one argument, so first and last agree - direct calls outside that precondition are not covered"

  i.mutation "e92265a23f2fc9af",
             subject: "Saboteur::SubjectFinder#walk_heredoc_eval",
             reason: "equivalent for the current consumers only: subjects take file, source and offsets from ctx[:file] and the failure path returns silently; the dropped filepath does change AST metadata (a def with __FILE__ reads differently), which no current lib consumer reads"

  i.mutation "8387aa82e7a9b074",
             subject: "Saboteur::Engine::TestGuess#expand_mapped",
             reason: "equivalent: literal spec values are existence-validated when the map loads, so expand_mapped only " \
                     "sees existing literals without glob metacharacters, and Dir.glob of such a path returns exactly it"

  i.mutation "bb377adb7ae9ce54",
             subject: "Saboteur::Engine::SubjectSelection#drop_intentionally_untested",
             reason: "equivalent: each returns the receiver and join(', ') stringifies via Subject#to_s (the id), " \
                     "so the note reads identically to map(&:id)"

  i.mutation "bafd61e973bfc9a9",
             subject: "Saboteur::CLI::Presets#preset",
             reason: "equivalent: ARGV entries are strings, so first.nil? and last.nil? agree: both are true only for an empty argv"

  i.mutation "4b8734a9a70da302",
             subject: "Saboteur::Engine::Scheduler#retry_longer",
             reason: "budget_capped clamps retry_timeout to <= longer, so < and != agree on every reachable value"

  i.mutation "e9effc360ce327fb",
             subject: "Saboteur::Engine::BaselineGuard#budget_stopped?",
             reason: "admitted is clamped to <= the configured phase timeout, so < and != agree on every reachable value"

  i.mutation "2e122d7fa55e9c86",
             subject: "Saboteur::Engine::CoverageStore#budget_stopped?",
             reason: "admitted is clamped to <= the configured phase timeout, so < and != agree on every reachable value"

  i.mutation "5e4ced5440585f8a",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "budget_capped clamps its result to <= the given timeout, so < and != agree on every reachable value"

  i.mutation "38af4993fb255820",
             subject: "Saboteur::Engine::Scheduler#unchanged_timing",
             reason: "budget_capped clamps its result to <= the baseline timeout, so < and != agree on every reachable value"

  i.mutation "452346af9d7dfcf0",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "the 0.0 runtime of a check that never forked is discarded: as_unverified keeps the kill's own runtime"

  i.mutation "dc826f708439e417",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "the 0.0 runtime of a check that never forked is discarded: as_unverified keeps the kill's own runtime"

  i.mutation "4c76f1fb164340ce",
             subject: "Saboteur::Engine::VerdictCheck#check_sequences",
             reason: "equivalent: the block's side effects populate the accumulators and the enumerator's return value is unused, so each and map agree"

  i.mutation "acc82bd84e367b90",
             subject: "Saboteur::Engine::VerdictCheck#check_claims",
             reason: "equivalent: the block's side effects populate the accumulators and the enumerator's return value is unused, so each and map agree"

  i.mutation "d5337bfe1d6b9951",
             subject: "Saboteur::Reporter::Terminal#list",
             reason: "equivalent: the block's puts side effects are the whole behavior and the return value is unused, so each and map agree"

  i.mutation "ada60709111b1e56",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: at the bound a[i] or b[j] is nil, so the equality fails either way"

  i.mutation "c4b7fbdde5c05b17",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: at the bound a[i] or b[j] is nil, so the equality fails either way"

  i.mutation "41cd39a78233765a",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: when a[i] != b[j], table[i][j] is the max of its neighbours, so comparing with it or with table[i][j + 1] picks the same branch"

  i.mutation "4fd308f9615f7631",
             subject: "Saboteur::Reporter::Diff#lcs_table",
             reason: "equivalent: extra rows/columns are never read, and a uniform base value shifts every LCS entry equally"

  i.mutation "ffa2ca5ba8f60668",
             subject: "Saboteur::Reporter::Diff#lcs_table",
             reason: "equivalent: extra rows/columns are never read, and a uniform base value shifts every LCS entry equally"

  i.mutation "52ddbd3e76910161",
             subject: "Saboteur::Reporter::Diff#lcs_table",
             reason: "equivalent: extra rows/columns are never read, and a uniform base value shifts every LCS entry equally"

  i.mutation "63886f1a7efa1eeb",
             subject: "Saboteur::Reporter::Diff#lcs_table",
             reason: "equivalent: extra rows/columns are never read, and a uniform base value shifts every LCS entry equally"

  i.mutation "091be99cfaabd312",
             subject: "Saboteur::Reporter::Diff#lcs_table",
             reason: "equivalent: scaling every match weight preserves every comparison in the LCS table"

  i.mutation "6942889ab35d8e7e",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: with no changes there are no ranges, so the method returns [] anyway"

  i.mutation "db9eb05715b7f0af",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: the slice ops[from..to] clips an end past the last op"

  i.mutation "cdd1aad6b8682369",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: the slice ops[from..to] clips an end past the last op"

  i.mutation "ef78c9e34814b478",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: ranges arrive sorted, so the new end is never below the previous range end"

  i.mutation "14689cacf3add21b",
             subject: "Saboteur::Reporter::Terminal#kill_causes",
             reason: "equivalent: only killed results carry a kill_cause, so status == :killed || kill_cause selects the same results"

  i.mutation "908a7d9f7906bc19",
             subject: "Saboteur::Reporter::Terminal#shown",
             reason: "equivalent: the hidden count is only printed when positive, and -1 is not"

  i.mutation "ac98a6c895a3e3b8",
             subject: "Saboteur::Reporter::Terminal#shown",
             reason: "equivalent: the sort key keeps the same order (ignored after live, coarse before fine)"

  i.mutation "87077462eb4bee86",
             subject: "Saboteur::Reporter::Terminal#shown",
             reason: "equivalent: the sort key keeps the same order (ignored after live, coarse before fine)"

  i.mutation "c1a541ae7499c128",
             subject: "Saboteur::Reporter::Terminal#shown",
             reason: "equivalent: the sort key keeps the same order (ignored after live, coarse before fine)"

  i.mutation "73b795bf8d86fda1",
             subject: "Saboteur::Reporter::Terminal#shown",
             reason: "equivalent: the sort key keeps the same order (ignored after live, coarse before fine)"

  i.mutation "1c63f9e764f00ada",
             subject: "Saboteur::Engine::Scheduler.prioritize",
             reason: "equivalent: the default only shifts every never-killer by the same amount, so the order is the same"

  i.mutation "ffdd70017e77a3e4",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: prioritize reads killers with fetch, which ignores the hash default"

  i.mutation "39e373554ad98f5f",
             subject: "Saboteur::Engine::Scheduler#all_reused",
             reason: "equivalent: without a cache every reuse returns nil, so the pass ends at the first mutant; only speed differs"

  i.mutation "30f5bc370f581852",
             subject: "Saboteur::Engine::Scheduler#execute",
             reason: "equivalent: counting each kill as 2 keeps the same order of killers"

  i.mutation "a7573a705c635da0",
             subject: "Saboteur::MutationSource::Builtin#rescues_everything?",
             reason: "equivalent: nil and false are both falsy for the caller"

  i.mutation "e962119c0314fa3d",
             subject: "Saboteur::MutationSource::Builtin#visit_statements",
             reason: "equivalent: the loop never sees an empty sequence, so != 1 and > 1 agree"

  i.mutation "908676542a888c9d",
             subject: "Saboteur::MutationSource::Builtin#mutate_call",
             reason: "equivalent: only binary calls are named like a comparison or arithmetic operator in practice"

  i.mutation "4cc9db1f1c23f253",
             subject: "Saboteur::MutationSource::Builtin#mutate_call",
             reason: "equivalent: Prism always gives ! a receiver"

  i.mutation "557d74f40af55855",
             subject: "Saboteur::MutationSource::Builtin#mutate_number",
             reason: "equivalent: add drops a replacement whose text equals the original"

  i.mutation "0bc08834912bc67d",
             subject: "Saboteur::Selection::CoverageMap#test_order",
             reason: "equivalent: memoization only; tests never change after construction"

  i.mutation "65fbe2a08ec0b22f",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: git quotes a whole path, so a path that starts with a quote also ends with one"

  i.mutation "bd07c16b6d849639",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: git quotes a whole path, so a path that starts with a quote also ends with one"

  i.mutation "515df7ed36a74cbe",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: start_with?(\"\") is always true, reducing the guard to the end_with? check ignored above"

  i.mutation "47379b177b6b3178",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: end_with?(\"\") is always true, reducing the guard to the start_with? check ignored above"

  i.mutation "d730c8559c9f15b3",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: .b only retags the string and the force_encoding right after overwrites the tag; bytes never change"

  i.mutation "168aa39476e05d6b",
             subject: "Saboteur::Selection::UntrackedChanges#union",
             reason: "equivalent: the block's return value is unused, so each and map run the same side effects"
  i.mutation "0483ba48e0fe025b",
             subject: "Saboteur::Selection::UntrackedChanges#union",
             reason: "equivalent: the block's return value is unused, so each and map run the same side effects"

  i.mutation "40c51d744af42a0e",
             subject: "Saboteur::Selection::UntrackedChanges#count_lines",
             reason: "equivalent: IO#read with a positive length is nil at EOF and never empty, so the empty-chunk arm is unreachable; the guard only bounds a no-arg-read mutant's spin"

  i.mutation "55c265f587f07d8f",
             subject: "Saboteur::Engine::DiffScope#distance_for",
             reason: "equivalent: at first == changed.end the subtraction is 0, exactly the overlap arm's answer, so > and >= agree everywhere"

  i.mutation "b6971b0205b221fb",
             subject: "Saboteur::Engine::DiffScope#distance_for",
             reason: "equivalent: at last == changed.begin the subtraction is 0, exactly the overlap arm's answer, so < and <= agree everywhere"

  i.mutation "bde3ce6eba713256",
             subject: "Saboteur::Engine::SubjectSelection#find",
             reason: "equivalent: the block's return value is unused, so each and map run the same side effects"

  i.mutation "2a03e98d1de4dcfb",
             subject: "Saboteur::Engine::SubjectSelection#by_pattern",
             reason: "equivalent: the block's return value is unused, so each and map run the same side effects"

  i.mutation "33b888a35f749d05",
             subject: "Saboteur::Engine::TestGuess#call_all",
             reason: "equivalent: the block's return value is unused, so each and map run the same side effects"

  i.mutation "1585456d1fd69b1a",
             subject: "Saboteur::Engine::SubjectSelection#report_unchanged_syntax",
             reason: "equivalent: Subject#to_s is its id, so joining subjects reads the same as joining their ids"

  i.mutation "b3fd9ed8d22fac26",
             subject: "Saboteur::Engine::SubjectSelection#report_unchanged_syntax",
             reason: "equivalent: Subject#to_s is its id, and the block's return value is only joined, so map and each read the same"

  i.mutation "ef5c88b04ed4987a",
             subject: "Saboteur::Engine::SubjectSelection#drop_intentionally_untested",
             reason: "equivalent: Subject#to_s is its id, so joining subjects reads the same as joining their ids"

  i.mutation "460c99badd064fe9",
             subject: "Saboteur::Frameworks::Rails#sqlite_absolute",
             reason: "equivalent: File.expand_path ignores the root for an absolute path, so dropping the early return changes nothing"

  i.mutation "df42644a6903198b",
             subject: "Saboteur::Frameworks::Rails#step_backup",
             reason: "equivalent: any negative page count steps through every remaining page"

  i.mutation "843c81e64fce006d",
             subject: "Saboteur::Frameworks::Rails#with_sqlite",
             reason: "equivalent here: sqlite3 is always loaded before this runs - the covering spec requires it, and a Rails app with a sqlite adapter has it loaded"

  i.mutation "6b4e7009a196f437",
             subject: "Saboteur::Report#majority_errored?",
             reason: "equivalent: with nothing executed the count is 0 and 0.fdiv(0) is NaN, which is not > 0.5 either"

  i.mutation "fb7088c67b8733c9",
             subject: "Saboteur::Frameworks::Rails#restore_memory_databases",
             reason: "equivalent: with an empty snapshot map the pool loop finds no matching config and skips every pool, as the early return does"

  i.mutation "bee95f3ac9a8f5f9",
             subject: "Saboteur::ConfigFile#unknown_setting_message",
             reason: "equivalent: the loaded file is always in the error backtrace, so find never returns nil"

  i.mutation "d9d499d476d8af9a",
             subject: "Saboteur::ConfigFile#unknown_setting_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"

  i.mutation "5111b03cc7e5e041",
             subject: "Saboteur::ConfigFile#name_error_message",
             reason: "equivalent: the loaded file is always in the error backtrace, so find never returns nil"

  i.mutation "ec59171e616b5f44",
             subject: "Saboteur::ConfigFile#name_error_message",
             reason: "equivalent: a raised error always has backtrace locations"

  i.mutation "0ad6200ca7b38104",
             subject: "Saboteur::ConfigFile#name_error_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"

  i.mutation "2e6104adf15e225f",
             subject: "Saboteur::CustomMap#glob_entry",
             reason: "equivalent: best is never empty, so != 1 and > 1 agree"

  i.mutation "278670ade53a7881",
             subject: "Saboteur::CustomMap#resolve",
             reason: "equivalent: a spec with a backreference only validates under a Regexp key, where match is always present"

  i.mutation "ac6cf2cb71251211",
             subject: "Saboteur::IgnoreList.name_error_message",
             reason: "equivalent: a raised error always has backtrace locations"

  i.mutation "7ca498e2b9fbbacc",
             subject: "Saboteur::IgnoreList.name_error_message",
             reason: "equivalent: the loaded file is always in the error backtrace, so find never returns nil"

  i.mutation "20e8e8fdb8ca509e",
             subject: "Saboteur::IgnoreList.name_error_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"

  i.mutation "44d44315871fd74d",
             subject: "Saboteur::CustomMap.name_error_message",
             reason: "equivalent: a raised error always has backtrace_locations, so dropping the safe navigation changes nothing"

  i.mutation "25c51526ec8e79ce",
             subject: "Saboteur::CustomMap.name_error_message",
             reason: "equivalent: the find result is always the loaded file's frame, so dropping the safe navigation changes nothing"

  i.mutation "0031eaebba2ea9ab",
             subject: "Saboteur::CustomMap.name_error_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"

  i.mutation "50aeb1c93f0d6b6c",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1, 2).first is the same frame as caller_locations(1, 1).first"

  i.mutation "db8db6c223204ba6",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1) starts at the same frame and .first is unchanged"

  i.mutation "6fdb2fe6bf77bf08",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1) starts at the same frame and .first is unchanged"

  i.mutation "433983b0f5dac95d",
             subject: "Saboteur::IgnoreList.unknown_directive_message",
             reason: "equivalent: the loaded file is always in the error backtrace, so find never returns nil"

  i.mutation "a1c0d420583dc184",
             subject: "Saboteur::IgnoreList.unknown_directive_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"




  i.mutation "d5d83ae928db4190",
             subject: "Saboteur::Engine#candidate_lists",
             reason: "wiring verified end-to-end: without hazard_guard the danger-fixture e2e wipes its copy and fails; subprocess runs are invisible to in-process coverage"




  i.mutation "488d29fe1b3f490f",
             subject: "Saboteur::Engine::Distribution#run",
             reason: "equivalent: jobs is validated >= 1, so <= and == agree on every reachable value"

  i.mutation "266e4305edcac0b1",
             subject: "Saboteur::Engine::Canary#inventory",
             reason: "equivalent: forcing the git branch still reaches walk_files through the ls-files failure fallback in a non-repository, yielding the same inventory"

  i.mutation "9bbfe3d7a6763928",
             subject: "Saboteur::Engine::Canary#git?",
             reason: "equivalent: with the condition forced true, a tree without .git still falls back to walk_files when git ls-files fails"

  i.mutation "92187871045409ad",
             subject: "Saboteur::Engine::Canary#git?",
             reason: "equivalent: replacing the git binary probe with the directory check only differs when git is absent, and saboteur requires git for diffs and baselines"








  i.mutation "d68346ea9d02b690",
             subject: "Saboteur::Engine::Canary#walk_files",
             reason: "equivalent: the reject operands are pure predicates, so | returns the same boolean as ||"

  i.mutation "2689f9db0bec4712",
             subject: "Saboteur::Engine::Distribution#decode",
             reason: "equivalent: encode always writes rejected_kill, so the fetch default never fires for same-version workers"

  i.mutation "e26320eab32dc139",
             subject: "Saboteur::Engine::Distribution#decode",
             reason: "equivalent: encode always writes rejected_kill, so fetch with and without the default reads the same present key"

  i.mutation "efe71ae606835faa",
             subject: "Saboteur::MutationSource::HazardGuard#hazard_spans",
             reason: "equivalent: descending into a hazardous call only records spans nested inside the outer one, and an edit covering the outer span covers them too, so kept/suppressed outcomes are unchanged"




  i.mutation "264eeaf9a5ccfb11",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: removing the all-reused shortcut still reuses each cached verdict; checked does not run neutral checks for reused verdicts"

  i.mutation "5c4511ee458a0b62",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: initial slowdown 1 and 1.0 produce the same float deadline when multiplied by recorded runtime"

  i.mutation "aff3fcccde575b60",
             subject: "Saboteur::Engine::Scheduler#reuse",
             reason: "equivalent: no covering tests means no stored cache verdict; execute then returns the same uncoverable result"

  i.mutation "2775afca28a11bfe",
             subject: "Saboteur::Selection::CoverageMap#sort_test_ids",
             reason: "equivalent: ids come from by_method/by_line values, which store indices into tests, so order.fetch always hits and the default is unreachable"

  i.mutation "58015bc90175b563",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent: walking unrelated AST children still returns nil; the InNode pattern containment check prevents them from supplying lines for this edit"

  i.mutation "8f347a8e928e9ef5",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent: Prism's sibling locations are disjoint, so at most one child contains the edit; returning its nil immediately is the same as finishing the loop with nil"

  i.mutation "c52104bcd93c6fc2",
             subject: "Saboteur::Selection::CoverageMap#tests_for_branches",
             reason: "equivalent: branch spans always have four coordinates, so span[2, 3] and span[2, 2] both return the final two coordinates"
  i.mutation "df73cda19a6c56f3",
             subject: "Saboteur::Engine::Scheduler#uncoverable",
             reason: "equivalent: unloadable receives exactly one candidate here, so first and last return the same result"

  i.mutation "eb6af4aef069613b",
             subject: "Saboteur::Engine::Scheduler#uncoverable",
             reason: "equivalent: skip_all receives exactly one candidate here, so first and last return the same result"

  i.mutation "560fd49376706c7c",
             subject: "Saboteur::Config#validate_fail_fast!",
             reason: "equivalent: jobs is validated as at least 1 before this check, so jobs > 1 and jobs != 1 agree for every value that reaches it"

  i.mutation "da7d0b0cd48bc0f6",
             subject: "Saboteur::Reporter::SurvivorList#lines",
             reason: "equivalent: the mutants on one line belong to one subject and share its id and source line, so the first and the last print the same header"

  i.mutation "bc3002bc8baaf16b",
             subject: "Saboteur::Reporter::SurvivorList#evidence_group",
             reason: "equivalent: a group is keyed by covering tests, reuse and changed lines, so every member prints the same evidence"

  i.mutation "947651810f34ed47",
             subject: "Saboteur::Preview#planned",
             reason: "equivalent: at the exact cap, >= records a zero-count omission; preview only sums omission counts, so displayed counts and selected mutants are unchanged"

  i.mutation "dc44b78352b4ef54",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"

  i.mutation "2458d413d0870a98",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"

  i.mutation "4feff1bd217add5d",
             subject: "Saboteur::MutationSource::InterpolationRemoval#remove_parts",
             reason: "equivalent: the parts loop runs in statement position, so the collected array from map is discarded exactly like the each return"

  i.mutation "175c987f2f427da9",
             subject: "Saboteur::MutationSource::OperandReplacement#replace_operands",
             reason: "equivalent: the operand loop runs in statement position, so the collected array from map is discarded exactly like the each return"

  i.mutation "b16e5029f4fc994c",
             subject: "Saboteur::MutationSource::OperandReplacement#replace_operands",
             reason: "equivalent: splatting the ArgumentsNode wraps it as one element (it has no to_a), and its slice yields the sole argument's source for the one-argument infix calls binary? admits"

  i.mutation "fb3d8d74cffbaf81",
             subject: "Saboteur::MutationSource::OperatorVisit#visit",
             reason: "equivalent: the statement walk runs in statement position, so the collected array from map is discarded exactly like the each return"

  i.mutation "423d477387f24abf",
             subject: "Saboteur::MutationSource::OperatorVisit#visit",
             reason: "equivalent: the child walk runs in statement position, so the collected array from map is discarded exactly like the each return"

  i.mutation "1824b380776f6a59",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"

  i.mutation "981ed4f132e27c49",
             subject: "Saboteur::CrashReport#write_log",
             reason: "equivalent: write_log returns via an explicit return inside the block or nil after it; " \
                     "the block's write/rescue side effects are the whole behavior and the enumerator's return value is never used"

  i.mutation "57afcef173eb2eee",
             subject: "Saboteur::Config#coerce!",
             reason: "equivalent: the block's @values[key] assignment is the whole behavior and the enumerator's " \
                     "return is unused: coerce! ends with the test_selection assignment"

  i.mutation "23716ea3873be11e",
             subject: "Saboteur::Reporter::Terminal#errors",
             reason: "equivalent: the block's @out.puts side effects are the whole behavior and the enumerator's " \
                     "return value is unused"

  i.mutation "69ce317bab249ed6",
             subject: "Saboteur::Engine::Scheduler#checked",
             reason: "equivalent: the block's cache record side effects are the whole behavior and the chain's return value is discarded, so each and map agree"

  i.mutation "e96e7f1845d85ffa",
             subject: "Saboteur::CLI::RunBudgetOptions#parse_duration",
             reason: "equivalent: OptionParser declares no coercion for --max-duration, so parse_duration always receives a String and the defensive .to_s never changes the result"

  i.mutation "a00e405c28e686a0",
             subject: "Saboteur::Config#with",
             reason: "equivalent: initialize rejects non-string keys as unknown before the explicit list matters, " \
                     "and map(&:to_s) is the identity on the string keys that remain"

  i.mutation "0ab690443fd67fb4",
             subject: "Saboteur::ConstantReads#walk_children",
             reason: "equivalent: the block's walk side effects populate out and the enumerator's return value is unused, so each and map agree"

  i.mutation "aa7965c00918546f",
             subject: "Saboteur::ConstantReads#record",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"

  i.mutation "4d7c1f3822b15d79",
             subject: "Saboteur::ConstantReads#walk",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"

  i.mutation "b73c3bede9feae2f",
             subject: "Saboteur::ConstantReads#walk",
             reason: "equivalent: record checks in_def first, so for a def body the in_block flag never changes the outcome"

  i.mutation "5a498fc9faa8ba0e",
             subject: "Saboteur::ConstantReads#mentions?",
             reason: "equivalent: a wrongly-true mention only leads to a parse that finds no occurrence of the constant and records nothing, as the skip does"

  i.mutation "45d8896875d52512",
             subject: "Saboteur::ConstantSubjectFinder#reject_duplicates",
             reason: "equivalent: the block's writes counting side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "7f9c62be259a51ad",
             subject: "Saboteur::ConstantSubjectFinder#reject_duplicates",
             reason: "equivalent: the counts come from entries seen at least once, so > 1 and != 1 agree"

  i.mutation "d72efef2cacefa2c",
             subject: "Saboteur::ConstantSubjectFinder#reject_duplicates",
             reason: "equivalent: with no duplicates the skipped body subtracts and walks an empty list, both no-ops"

  i.mutation "300d6d1a7a7ac55b",
             subject: "Saboteur::ConstantSubjectFinder#reject_duplicates",
             reason: "equivalent: the block's out[:unsupported] << side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "da068d30705a7fe1",
             subject: "Saboteur::ConstantSubjectFinder#walk_children",
             reason: "equivalent: the block's walk side effects populate out and the enumerator's return value is unused, so each and map agree"

  i.mutation "03e1a219a69218ad",
             subject: "Saboteur::ConstantSubjectFinder#literal_value",
             reason: "equivalent: the extra step ends with value nil, and nil fails the HashNode/ArrayNode check just like the bare freeze call the loop would stop at"

  i.mutation "296e509071af2397",
             subject: "Saboteur::ConstantSubjectFinder#walk_factory",
             reason: "equivalent: the block's walk side effects populate out and the enumerator's return value is unused, so each and map agree"

  i.mutation "2ab9b5df9bbd2436",
             subject: "Saboteur::Engine::SubjectSelection#constant_subjects",
             reason: "equivalent: the block's subjects.concat side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "145023bdef6a8b5d",
             subject: "Saboteur::Engine::SubjectSelection#constant_subjects",
             reason: "equivalent: the block's warning side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "aca095f3c907a02e",
             subject: "Saboteur::Engine::SubjectSelection#attach_consumers",
             reason: "equivalent: the consumer_lines.empty? guard leaves only files whose reads all capture the value at load time, so any? and all? agree"

  i.mutation "d8b074df4d7df5c4",
             subject: "Saboteur::MutationSource::ConstantLiterals#initialize",
             reason: "equivalent: the Base initializer is stateless, so skipping it changes nothing"

  i.mutation "5c1090492053dc7a",
             subject: "Saboteur::MutationSource::ElementRemoval#visit",
             reason: "equivalent: the block's recording side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "e796c70885a9e545",
             subject: "Saboteur::MutationSource::ElementRemoval#visit",
             reason: "equivalent: the block's recording side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "21d74aaa5ab4c0f5",
             subject: "Saboteur::MutationSource::ElementRemoval#ending_for",
             reason: "equivalent: the closing bracket is never a separator comma, so ending at its start offset or the node's end offset finds the same separator"

  i.mutation "6412cfb15a08ea8a",
             subject: "Saboteur::MutationSource::ElementRemoval#ending_for",
             reason: "equivalent: a parsed literal always has a closing bracket, so the end_offset fallback is never taken"

  i.mutation "738912760a748098",
             subject: "Saboteur::MutationSource::ElementRemoval#ending_for",
             reason: "equivalent: a parsed literal always has a closing bracket, so &. and . agree"

  i.mutation "ad875ad601877dde",
             subject: "Saboteur::MutationSource::ElementRemoval#ending_for",
             reason: "equivalent on every supported Prism (>= 1.2, the gemspec range - operand_replacement.rb:39-40 already calls " \
                      "Node#end_offset directly): the location hop calls the same method"

  i.mutation "c03dc4c84077f549",
             subject: "Saboteur::MutationSource::EntryEdits#heredoc?",
             reason: "equivalent on every supported Prism (>= 1.2, the gemspec range - builtin.rb and the arid checks already call " \
                      "Node#slice directly): a heredoc node's own slice starts at its << opening and no other node with an opening_loc " \
                      "starts with <<, so node.slice answers the same"

  i.mutation "692c8de64cb30812",
             subject: "Saboteur::MutationSource::EntryEdits#entry_separator",
             reason: "equivalent on every supported Prism (>= 1.2, the gemspec range - operand_replacement.rb:39-40 already calls " \
                      "Node#end_offset directly): the location hop calls the same method"

  i.mutation "40b72924a9ba07d3",
             subject: "Saboteur::MutationSource::EntryEdits#entry_separator",
             reason: "equivalent on every supported Prism (>= 1.2, the gemspec range - operand_replacement.rb:39-40 already calls " \
                      "Node#end_offset directly): the location hop calls the same method"

  i.mutation "7c24d6a420d69ea0",
             subject: "Saboteur::MutationSource::EntryEdits#entry_separator",
             reason: "equivalent on every supported Prism (>= 1.2, the gemspec range - operand_replacement.rb:39 already calls " \
                      "Node#start_offset directly): the location hop calls the same method"

  i.mutation "c86d5a883ca1fd49",
             subject: "Saboteur::MutationSource::HazardGuard#vet_statements",
             reason: "equivalent: the block's vet_statement side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"
  # Over-matching a duplicate only demotes both writes, and a local assigned
  # in any branch is nil in the others: owner reads nil either way.
  i.mutation "c239b7bcac4b5ae4",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: owner is assigned in the if branch, so Ruby defines it as nil on the else path; the " \
                     "explicit owner = nil is documentation"
  # A vetted require takes exactly one argument, so first and last are the
  # same element whenever the length check passes; otherwise the
  # conjunction short-circuits before either is read.
  i.mutation "602ff9565dc30342",
             subject: "Saboteur::MutationSource::HazardGuard#vetted_call?",
             reason: "equivalent: arguments.length == 1 short-circuits the conjunction, and with one argument first and last are the same node"
end

Saboteur.ignore do |i|
  i.mutation "dab679873934108d",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: the owner local is parser-defined and already nil on the qualified-target branch, so dropping the assignment changes nothing"

  i.mutation "c3fab7a3832bbf23",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: downto(1) drops only the bare-name candidate, which always equals the write's own id that reject_duplicates already demotes"

  i.mutation "cd60f2f7ae856c4c",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: the extra depth -1 slice is nesting[0...-1], always a duplicate of an already-collected prefix candidate"

  i.mutation "7c9542268eff48fe",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: forcing the ternary only alters the nil-prefix candidate into a leading-:: id no subject can have, and that candidate is duplicates-covered"

  i.mutation "c42a64a08dcf8e04",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: a path write's source begins with its target, so node.slice and node.target.slice agree on the leading :: check"

  i.mutation "43da3e6c86de404d",
             subject: "Saboteur::ConstantSubjectFinder#record_unsupported",
             reason: "equivalent: the inclusive range only lengthens each prefix, producing the same candidate set minus the duplicates-covered bare-name candidate"

  i.mutation "228bba63e879c4f6",
             subject: "Saboteur::ConstantSubjectFinder#demote_ambiguous",
             reason: "equivalent: with an empty ambiguous list the demotion below selects nothing and is a no-op, so the guard's value never matters"

  i.mutation "71f06a1870dbfcb4",
             subject: "Saboteur::ConstantSubjectFinder#demote_ambiguous",
             reason: "equivalent: the loop's Unsupported-building side effects are the whole behavior and the enumerator's return value is unused, so each and map agree"

  i.mutation "782448b779a4bb89",
             subject: "Saboteur::Selection::GitDiff#drop_layout_only_lines",
             reason: "equivalent: without the slash the path starts with /, and git show reads base:.//path like base:./path"

  i.mutation "7929cdd27cf508cb",
             subject: "Saboteur::Selection::LayoutOnlyLines#base_line_of",
             reason: "equivalent: start <= line differs from start + count <= line only for a line inside a -b hunk, " \
                     "which restrict keeps through spaced_lines whatever same_tokens? answers"

  i.mutation "bf95736e576b6691",
             subject: "Saboteur::SubjectFinder#walk",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "76c21aa993019fba",
             subject: "Saboteur::SubjectFinder#walk",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "5df3e88b8674c139",
             subject: "Saboteur::SubjectFinder#walk_constant_assignment",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "6dcd94d3ceb84834",
             subject: "Saboteur::SubjectFinder#walk_constant_assignment",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "6d0178897b4f0480",
             subject: "Saboteur::SubjectFinder#mark_refinements",
             reason: "equivalent: each vs map on a side-effect-only loop that sets skip_reason; the array is discarded"

  i.mutation "c347d2a83fc6ab38",
             subject: "Saboteur::SubjectFinder#add_subject",
             reason: "equivalent: || false only normalizes nil to false; in_sclass is used in truthiness contexts only"

  i.mutation "41623d58ed9d06c8",
             subject: "Saboteur::SubjectFinder#sig_span",
             reason: "equivalent: Prism::Node#start_offset delegates to location.start_offset, so the chain cut is identical"

  i.mutation "e906e03768b70f99",
             subject: "Saboteur::SubjectFinder#sig_span",
             reason: "equivalent: Prism::Node#end_offset delegates to location.end_offset, so the chain cut is identical"

  i.mutation "7777f925324c357d",
             subject: "Saboteur::SubjectFinder#walk_singleton_class",
             reason: "equivalent: the sclass scope's path is never read: owner_path rejects sclass scopes and its header is hardcoded"

  i.mutation "a1ff930ecdd2a033",
             subject: "Saboteur::SubjectFinder#define_method_subject?",
             reason: "equivalent: the size == 1 guard above means first and last are the same argument"

  i.mutation "1bb4f84260161fd2",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: the finder only builds a define_method subject when node.block is a BlockNode, so the safe navigation never nil-guards"

  i.mutation "9a5e01816b209349",
             subject: "Saboteur::SubjectFinder#walk_statements",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "2037a2fdac063a81",
             subject: "Saboteur::SubjectFinder#walk_children",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "4aded400397da9fe",
             subject: "Saboteur::SubjectFinder#walk_call",
             reason: "equivalent: || false only normalizes nil to false; in_sclass is used in truthiness contexts only"

  i.mutation "d9a37d21f9adda1c",
             subject: "Saboteur::SubjectFinder#walk_call",
             reason: "equivalent: define_method_subject? accepts exactly one argument, so first and last are the same"

  i.mutation "51ecbca80e966840",
             subject: "Saboteur::SubjectFinder#walk_call",
             reason: "equivalent: sig_span: nil restates the keyword default in Subject#initialize"

  i.mutation "51495f10ee14f096",
             subject: "Saboteur::SubjectFinder#walk",
             reason: "equivalent: each vs map on a side-effect-only fallback walk loop; the collected array is discarded"

  i.mutation "b0aae921a2cfa19d",
             subject: "Saboteur::CLI#use_explicit_sources",
             reason: "equivalent: each and map both run the raising block over every test path; the collected array is unused"

  i.mutation "d689ef2e6305183f",
             subject: "Saboteur::SubjectFinder#owner_path",
             reason: "equivalent: nesting[index..] adds only the sclass scope itself to the any?(&:factory?) check, and a scope's kind is either :sclass or :factory, never both"

  i.mutation "70a77934c3856a1e",
             subject: "Saboteur::SubjectFinder#owner_path",
             reason: "equivalent: replacing (index + 1) with index only adds the sclass scope itself to the slice; an sclass scope never answers factory?, so any? is unchanged"

  i.mutation "4d3d5ac0703067d2",
             subject: "Saboteur::SubjectFinder#lexical_nesting",
             reason: "equivalent: replacing (index + 1) with index only adds the factory scope itself to the slice; a factory scope never answers sclass?, so none? is unchanged"

  i.mutation "8953e46e984e97b6",
             subject: "Saboteur::SubjectFinder#lexical_nesting",
             reason: "equivalent: index + 0 is index, which only adds the factory scope itself to the slice; a factory scope never answers sclass?, so none? is unchanged"

  i.mutation "036e4fb956df510f",
             subject: "Saboteur::Engine::ResultCache#digest_tests",
             reason: "equivalent: the following SHA256 hexdigest has a fixed width, so the dropped separator " \
                     "cannot blur field boundaries - a dependency-set change still changes the digest"

  i.mutation "9db3b9aa61e04166",
             subject: "Saboteur::Engine::ResultCache#digest_tests",
             reason: "equivalent: the trailing separator only separates entries, and entry count and content " \
                     "still change the digest - the next entry starts with its own path bytes"

  i.mutation "69e619be29339f30",
             subject: "Saboteur::Engine::ResultCache#digest_tests",
             reason: "equivalent: the block's digest-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

  i.mutation "485c590681bcde38",
             subject: "Saboteur::Selection::CoverageMap#files_for",
             reason: "equivalent: invert_coverage is a pure function of the map's frozen lines, so recomputing " \
                     "it on every call yields the identical hash the memo would have returned"

  i.mutation "c426c783724e596f",
             subject: "Saboteur::Selection::CoverageMap#invert_coverage",
             reason: "equivalent: the block's acc-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

  i.mutation "52e4bb172b350bc9",
             subject: "Saboteur::Selection::CoverageMap#invert_coverage",
             reason: "equivalent: the block's acc-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

end
