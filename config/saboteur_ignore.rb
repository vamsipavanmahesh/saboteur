# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivors accepted with a reason. Each digest is printed next to its survivor.
Saboteur.ignore do |i|
  # doctor_command.rb:12/14/15 opts.on flag<->help argument_swaps - OptionParser#on
  # classifies its string arguments by shape (a leading "-" makes a flag, anything
  # else a description), not by position, so the swap builds the identical parser
  # entry. Hand-probed: all three swaps applied together leave `doctor --help`
  # byte-identical and doctor_command + doctor + cli specs green (237 examples).
  i.mutation "455660d7ea53007b",
             subject: "Saboteur::CLI::DoctorCommand#doctor_parser",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not " \
                     "position - hand-applied swap leaves doctor --help byte-identical and 237 " \
                     "doctor/cli examples green"
  i.mutation "2084048de77c796f",
             subject: "Saboteur::CLI::DoctorCommand#doctor_parser",
             reason: "equivalent: same opts.on shape-classification swap on --suite - hand-applied " \
                     "mutant leaves doctor --help byte-identical and 237 doctor/cli examples green"
  i.mutation "5dd192fa4a2df7db",
             subject: "Saboteur::CLI::DoctorCommand#doctor_parser",
             reason: "equivalent: same opts.on shape-classification swap on --test - hand-applied " \
                     "mutant leaves doctor --help byte-identical and 237 doctor/cli examples green"

  # deep_source.rb:43 > -> >= - max is monotone, so the equal case reassigns the same value.
  # Strictly equivalent; hand-probed specs green and depth() identical across a battery.
  i.mutation "e6d7d3cf383401ec",
             subject: "Saboteur::DeepSource.depth",
             reason: "equivalent: when level == max the overwrite assigns the same value, " \
                     "leaving observable state unchanged; hand-probed depth() identical"
  # environment_hints.rb:34 - an empty BUNDLE_GEMFILE expands to the project root, which
  # never starts with <root>/gemfiles/, so dropping the `!setting.empty?` conjunct leaves
  # `under` false in exactly the same cases (verified by hand against the full
  # environment_hints spec file).
  i.mutation "b31f94f7f17ab049",
             subject: "Saboteur::EnvironmentHints#appraisal",
             reason: "equivalent: the empty-string conjunct is redundant because " \
                     "File.expand_path('', root) can never sit under <root>/gemfiles/"

  i.mutation "c4a41e4cf733a770",
             subject: "Saboteur::ConfigFile::Settings#integration=",
             reason: "equivalent: caller_locations(1, 2) widens only the frame count; fetch(0) reads the " \
                     "same first frame, so the reported line is unchanged. The line-changing variant " \
                     "(first argument 1 -> 2) is killed by the exact-line pins in config_file_spec " \
                     "(hand-applied: 3 failures including the :2 assignment-line example)"

  i.mutation "c99fc350a7d2d531",
             subject: "Saboteur::ConfigFile::Settings#integration=",
             reason: "equivalent: caller_locations(1, 1) returns a single-frame array, where fetch(-1) " \
                     "is fetch(0) - hand-applied mutant leaves all config_file examples green"

  i.mutation "a8c1471f8292f1f2",
             subject: "Saboteur::ConfigFile::Settings#integration=",
             reason: "equivalent: dropping the length argument gives caller_locations(1), whose first " \
                     "frame is the same one fetch(0) reads - hand-applied mutant leaves all " \
                     "config_file examples green"

  i.mutation "ba701d82f7059bc8",
             subject: "Saboteur::ConfigFile::Settings#integration=",
             reason: "equivalent: same caller_locations(1) shape from the other side of the comma - " \
                     "fetch(0) reads the same frame - hand-applied mutant leaves all config_file " \
                     "examples green"

  i.mutation "01788b3c7b37a3cb",
             subject: "Saboteur::MutationSource::HazardGuard#cite",
             reason: "equivalent: node.slice of a parsed Prism statement is never empty, so .lines.first is " \
                     "always a String and the .to_s only collapses a nil that cannot occur - hand-applied " \
                     "mutant leaves all hazard_guard and subject_selection examples green"

  i.mutation "69c095b81b8911f5",
             subject: "Saboteur::MutationSource::HazardGuard#cite",
             reason: "equivalent: in the bundled Prism, Node#start_line is a delegate of " \
                     "Node#location.start_line (verified against the project's prism), so dropping .location " \
                     "renders the same line number - hand-applied mutant leaves all examples green"

  i.mutation "ecc14ca9f634c6b4",
             subject: "Saboteur::Engine::HeredocSpans#collect",
             reason: "equivalent: the span push only runs for nodes whose opening marker starts with <<, " \
                     "and a heredoc string node's location begins at its opening marker (probed on Prism " \
                     "1.9.0: StringNode and InterpolatedStringNode slice == opening marker, node start_line " \
                     "== opening_loc.start_line), so dropping .opening_loc yields the same start line; " \
                     "hand-applied mutant leaves all 132 subject_selection examples green"
  i.mutation "fe711104425ed7f9",
             subject: "Saboteur::Frameworks::SqliteMemoryDatabase#fork_loss_hint",
             reason: "equivalent: forcing defined?(ActiveRecord::Base) true only defers the same nil - with " \
                     "ActiveRecord undefined the next line's ActiveRecord::Base reference raises NameError, " \
                     "which the method's own rescue StandardError turns into nil - hand-applied mutant leaves " \
                     "all sqlite_memory_database examples green"

  i.mutation "02f7817b2ef41452",
             subject: "Saboteur::AttributeFinder#walk",
             reason: "equivalent: the each result is discarded (visit recurses for effect); each and map run the same record/walk calls"

  i.mutation "75f0bf52ff86b7ce",
             subject: "Saboteur::AttributeFinder#walk",
             reason: "equivalent: the each result is discarded (visit recurses for effect); each and map run the same record/walk calls"

  i.mutation "192607563f4b49cb",
             subject: "Saboteur::AttributeFinder#record_macro",
             reason: "equivalent: the owner guard above returns unless owner_path(nesting) is non-nil, and a non-nil owner means nesting has a real scope, so nesting.last is never nil at the separator line"

  i.mutation "84c1c1d2c77efa3d",
             subject: "Saboteur::AttributeFinder#record_macro",
             reason: "equivalent: the each result is discarded (out is mutated for effect); each and map run the same body"

  i.mutation "647ef4d1e06082e0",
             subject: "Saboteur::AttributeFinder#record_macro",
             reason: "equivalent: the each result is discarded (out is mutated for effect); each and map run the same body"

  i.mutation "e28a064f17fcb078",
             subject: "Saboteur::AttributeFinder#walk_singleton_class",
             reason: "equivalent: the sclass scope's path is never rendered - owner_path skips sclass scopes and only kind: :sclass decides the separator - so the literal is inert"

  i.mutation "4431382aefb4312a",
             subject: "Saboteur::CLI::HistoryCommand#history_path",
             reason: "equivalent: UsageError < ConfigError, so the or-raise is caught by the method's own " \
                     "rescue ConfigError and re-raised with the rescue copy; probed live on the firing input " \
                     "(config.path returns nil): original and literal-emptied mutant raise the identical " \
                     "UsageError with the full rescue message"
  i.mutation "668e787880f87f22",
             subject: "Saboteur::MutationSource::MethodSwap#visit_used_children",
             reason: "equivalent: visit_used_children array of child results is discarded by its only caller (visit); each and map run the same used-wrapped recursion"

  i.mutation "6799cc120401b50d",
             subject: "Saboteur::MutationSource::MethodSwap#visit_statements",
             reason: "equivalent: each_with_index bounds index to 0..size-1, where index < size-1 and index != size-1 agree on every reachable value"
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

  i.mutation "486ad51016f34af2",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "budget_capped clamps its result to <= the given timeout, so < and != agree on every reachable value"

  i.mutation "38af4993fb255820",
             subject: "Saboteur::Engine::Scheduler#unchanged_timing",
             reason: "budget_capped clamps its result to <= the baseline timeout, so < and != agree on every reachable value"

  i.mutation "2c0b34a1f6194653",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "the 0.0 runtime of a check that never forked is discarded: as_unverified keeps the kill's own runtime"

  i.mutation "7c5f9f0eb018b358",
             subject: "Saboteur::Engine::Scheduler#unchanged_runner",
             reason: "the 0.0 runtime of a check that never forked is discarded: as_unverified keeps the kill's own runtime"




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


  i.mutation "1c63f9e764f00ada",
             subject: "Saboteur::Engine::Scheduler.prioritize",
             reason: "equivalent: the default only shifts every never-killer by the same amount, so the order is the same"

  i.mutation "1ca4289bf90fb951",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: prioritize reads killers with fetch, which ignores the hash default"

  i.mutation "39e373554ad98f5f",
             subject: "Saboteur::Engine::Scheduler#all_reused",
             reason: "equivalent: without a cache every reuse returns nil, so the pass ends at the first mutant; only speed differs"

  i.mutation "a7573a705c635da0",
             subject: "Saboteur::MutationSource::Builtin#rescues_everything?",
             reason: "equivalent: nil and false are both falsy for the caller"

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


  i.mutation "40c51d744af42a0e",
             subject: "Saboteur::Selection::UntrackedChanges#count_lines",
             reason: "equivalent: IO#read with a positive length is nil at EOF and never empty, so the empty-chunk arm is unreachable; the guard only bounds a no-arg-read mutant's spin"

  i.mutation "55c265f587f07d8f",
             subject: "Saboteur::Engine::DiffScope#distance_for",
             reason: "equivalent: at first == changed.end the subtraction is 0, exactly the overlap arm's answer, so > and >= agree everywhere"

  i.mutation "b6971b0205b221fb",
             subject: "Saboteur::Engine::DiffScope#distance_for",
             reason: "equivalent: at last == changed.begin the subtraction is 0, exactly the overlap arm's answer, so < and <= agree everywhere"




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

  i.mutation "433983b0f5dac95d",
             subject: "Saboteur::IgnoreList.unknown_directive_message",
             reason: "equivalent: the loaded file is always in the error backtrace, so find never returns nil"

  i.mutation "a1c0d420583dc184",
             subject: "Saboteur::IgnoreList.unknown_directive_message",
             reason: "equivalent: the backtrace starts at the loaded file, so find { true } returns the same location"

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



  i.mutation "efe71ae606835faa",
             subject: "Saboteur::MutationSource::HazardGuard#hazard_spans",
             reason: "equivalent: descending into a hazardous call only records spans nested inside the outer one, and an edit covering the outer span covers them too, so kept/suppressed outcomes are unchanged"

  i.mutation "264eeaf9a5ccfb11",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: removing the all-reused shortcut still reuses each cached verdict; checked does not run neutral checks for reused verdicts"

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



  i.mutation "560fd49376706c7c",
             subject: "Saboteur::Config#validate_fail_fast!",
             reason: "equivalent: jobs is validated as at least 1 before this check, so jobs > 1 and jobs != 1 agree for every value that reaches it"

  i.mutation "da7d0b0cd48bc0f6",
             subject: "Saboteur::Reporter::SurvivorList#lines",
             reason: "equivalent: the mutants on one line belong to one subject and share its id and source line, so the first and the last print the same header"

  i.mutation "bc3002bc8baaf16b",
             subject: "Saboteur::Reporter::SurvivorList#evidence_group",
             reason: "equivalent: a group is keyed by covering tests, reuse and changed lines, so every member prints the same evidence"

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


  i.mutation "423d477387f24abf",
             subject: "Saboteur::MutationSource::OperatorVisit#visit",
             reason: "equivalent: the child walk runs in statement position, so the collected array from map is discarded exactly like the each return"

  i.mutation "1824b380776f6a59",
             subject: "Saboteur::Subject#pattern_coverage_lines",
             reason: "equivalent on current Prism, where Node#start_line exists: the location hop stays because Prism 1.2, the gemspec minimum, has no Node#start_line"




  i.mutation "996853fcc7690d62",
             subject: "Saboteur::Engine::Scheduler#call",
             reason: "equivalent: results holds at most one entry per run candidate, so size can be shorter than candidates but never longer, and < and != agree (hand-confirmed by QA)"

  i.mutation "406cbdb97f3b37da",
             subject: "Saboteur::Engine::Scheduler#checked",
             reason: "equivalent: #checked re-assigns @confirming_truncation = truncated at entry (scheduler.rb:98) before the only readers (rerun_in_prefix, unchanged_runner) run, so the ensure value never leaks into another subject (driven: survives the full scheduler spec, including the two-subject flag spec)"

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




  i.mutation "aca095f3c907a02e",
             subject: "Saboteur::Engine::SubjectSelection#attach_consumers",
             reason: "equivalent: the consumer_lines.empty? guard leaves only files whose reads all capture the value at load time, so any? and all? agree"

  i.mutation "d8b074df4d7df5c4",
             subject: "Saboteur::MutationSource::ConstantLiterals#initialize",
             reason: "equivalent: the Base initializer is stateless, so skipping it changes nothing"


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

  i.mutation "5df3e88b8674c139",
             subject: "Saboteur::SubjectFinder#walk_constant_assignment",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

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

  i.mutation "907c77941a63c124",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: CallNode subjects come only from walk_call after call_defined_method? passed, whose literal_name? guard reads node.arguments&.arguments&.first, so node.arguments is never nil here (live-probed: driven against the subject specs under full body_node coverage)"

  i.mutation "e548f0a66ab5e680",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: the literal_name? gate in call_defined_method? makes node.arguments non-nil for every CallNode subject, so the arguments array is always present and the second safe navigation never fires (live-probed)"

  i.mutation "807b99fc346c595d",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: Prism::ArgumentsNode#find enumerates the same argument nodes as #arguments.find - on `scope :x, -> { 1 }` both return the identical LambdaNode (live-probed) - and node is the subject's own node, never nil"

  i.mutation "f9d3343f983e9d61",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: Prism::ArgumentsNode#find enumerates the same nodes as #arguments.find (live-probed identical LambdaNode), and node.arguments is non-nil via the literal_name? gate in call_defined_method?"

  i.mutation "8a1aa6eb90d0c1d1",
             subject: "Saboteur::Subject#body_node",
             reason: "equivalent: call_defined_method? admits define_method only with a BlockNode block and scope/define_singleton_method only with a LambdaNode argument or a block, so (lambda || node.block) is never nil for a subject (live-probed)"

  i.mutation "9a5e01816b209349",
             subject: "Saboteur::SubjectFinder#walk_statements",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"

  i.mutation "2037a2fdac063a81",
             subject: "Saboteur::SubjectFinder#walk_children",
             reason: "equivalent: each vs map on a side-effect-only walk loop; the collected array is discarded"


  i.mutation "ef239b357ad7b089",
             subject: "Saboteur::RefinementActivations::Site#covers?",
             reason: "equivalent: a subject can never start on the using call's own first byte, so > and >= agree (live-probed: survives the full refinement specs)"

  i.mutation "4766d590fd60b0d1",
             subject: "Saboteur::RefinementActivations::Site#covers?",
             reason: "equivalent: a subject cannot start exactly at the scope's end offset - the scope's `end` keyword occupies the bytes before it - so < and <= agree (live-probed)"

  i.mutation "3358f408831faf79",
             subject: "Saboteur::RefinementActivations.mark",
             reason: "equivalent: with no sites the any?/each below are no-ops, so the empty-sites early return only skips work (live-probed)"

  i.mutation "85af2fd1d4997170",
             subject: "Saboteur::RefinementActivations.mark",
             reason: "equivalent: removing the empty-sites return falls through to the same no-op any?/each over zero sites (live-probed)"

  i.mutation "06be8ce5bdca364f",
             subject: "Saboteur::RefinementActivations.mark",
             reason: "equivalent: each vs map on a side-effect-only skip-marking loop; the collected array is discarded (live-probed)"

  i.mutation "d2d2cb9da8ecc4bc",
             subject: "Saboteur::SubjectFinder#walk_call",
             reason: "equivalent: sig_span: nil restates the keyword default in Subject#initialize (subject.rb:42-43); live-probed: the pair removal survives the subject and subject_finder specs"

  i.mutation "51495f10ee14f096",
             subject: "Saboteur::SubjectFinder#walk",
             reason: "equivalent: each vs map on a side-effect-only fallback walk loop; the collected array is discarded"


  i.mutation "fd1253fb224794ff",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; dropping the size guard changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"

  i.mutation "7955f85bfb432312",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; size >= 1 changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"

  i.mutation "17068564717dfd5d",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; size != 1 changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"

  i.mutation "50e206442fdad447",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; size > 0 changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"

  i.mutation "1734bd1a82e156ea",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; a bare size (always truthy) changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"

  i.mutation "f719923d733c3339",
             subject: "Saboteur::Engine::Scheduler#reordered",
             reason: "equivalent: the size guard only matters for lists of 0 or 1 tests, where rotate " \
                     "returns the same list; a bare 1 (always truthy) changes no output (probed over sizes " \
                     "0-6 and 300 seeds, no divergence)"
  i.mutation "ce91efaab8362061",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: shadowed's only non-nil assignment is guarded by path != scopes.first and scopes " \
                     "holds just the owner, so shadowed == scope is never true and swapping the dead disjunct changes nothing"

  i.mutation "dc592bbbeadec650",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: shadowed's only non-nil assignment is guarded by path != scopes.first and scopes " \
                     "holds just the owner, so shadowed == scope is already always false"

  i.mutation "5f8ed39d3c1a6df3",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: overwriting shadowed is unobservable: a shadow crossing into the owner subtree is " \
                     "lifted at the boundary first, and a nested writer's path only extends the current shadow's " \
                     "lexical subtree, so the none? classification it feeds never changes"

  i.mutation "c2cd20ea2074e488",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: scopes holds exactly one element (the owner), so first and last agree"

  i.mutation "6c755a9350011f9b",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: scopes holds exactly one element (the owner), so any? and all? agree"

  i.mutation "698e9c03fc5cfa99",
             subject: "Saboteur::ConstantReads#walk_scope",
             reason: "equivalent: the none? check only runs when path is inside the owner subtree, and a live shadow " \
                     "there was set inside the subtree: shadows propagate only down their setter's lexical tree " \
                     "and outside shadows lift at the owner boundary. A string-prefix shadow that is not under " \
                     "the owner (M2 vs M) sits in a sibling or ancestor subtree - siblings never share shadow " \
                     "state, ancestors are shorter than the owner so start_with? fails identically - so the " \
                     "bare-prefix check agrees on every reachable shadowed"

  i.mutation "a239e75a818e5e27",
             subject: "Saboteur::Engine::TestGuess#defined_constants",
             reason: "equivalent: sole consumer is any? over ConstantReads.across; .uniq removes only byte-identical DefinedConstant tuples, and a duplicate tuple yields the same across result"
  i.mutation "ab2717e302f1bbf4",
             subject: "Saboteur::Subject#initialize",
             reason: "equivalent: prism nodes delegate start_offset to their location, so node.start_offset is node.location.start_offset"

  i.mutation "92b037ffed4fece1",
             subject: "Saboteur::Subject#initialize",
             reason: "equivalent: prism nodes delegate end_offset to their location, so node.end_offset is node.location.end_offset"

  i.mutation "eb627023b070245d",
             subject: "Saboteur::Subject#initialize",
             reason: "equivalent: an unread ivar is nil, so dropping @skip_reason = nil leaves the same default"

  i.mutation "fc9db74a0df1ef3e",
             subject: "Saboteur::Subject#source",
             reason: "equivalent: ||= and = compute the same bytes from an immutable file_source; only the memo differs"

  i.mutation "d6f4737bbb1c4026",
             subject: "Saboteur::Subject#rescuing?",
             reason: "equivalent: the parser only allows else with rescue, so else_clause non-nil implies rescue_clause non-nil and the extra check never decides"

  i.mutation "e7a053a591c446e5",
             subject: "Saboteur::Subject#surrounding_text",
             reason: "equivalent: force_encoding mutates in place, so each returns the same two already-forced strings map would collect"

  i.mutation "06dab602bbc57fd1",
             subject: "Saboteur::Subject#coverage_lines_for",
             reason: "equivalent: edit.end_byte - 1 is always >= edit.start_byte for a nonempty edit, so dropping it from the max changes nothing"

  i.mutation "4399e0c4953e5bb3",
             subject: "Saboteur::Subject#coverage_lines_for",
             reason: "equivalent: the edit lies inside the statement, so last >= first always and dropping first from the max changes nothing"

  i.mutation "e8d05de3635878b8",
             subject: "Saboteur::Subject#contains_edit?",
             reason: "equivalent: prism nodes delegate start_offset to their location"

  i.mutation "15307bd521a10280",
             subject: "Saboteur::Subject#contains_edit?",
             reason: "equivalent: prism nodes delegate end_offset to their location"

  i.mutation "d689ef2e6305183f",
             subject: "Saboteur::SubjectFinder#owner_path",
             reason: "equivalent: nesting[index..] adds only the sclass scope itself to the any?(&:factory?) check, and a scope's kind is either :sclass or :factory, never both"

  i.mutation "70a77934c3856a1e",
             subject: "Saboteur::SubjectFinder#owner_path",
             reason: "equivalent: replacing (index + 1) with index only adds the sclass scope itself to the slice; an sclass scope never answers factory?, so any? is unchanged"
  i.mutation "13bf3b4f2a6e9976",
             subject: "Saboteur::MutationSource::RegexReplacement#scan_anchors_and_quantifiers",
             reason: "equivalent: index strictly increases by 1 or 2 and a valid regex never ends in a lone backslash (RegexpError: too short escape sequence), so index <= bytes.size always; the extra <= iteration reads nil, takes the else branch and yields nothing"

  i.mutation "c71c47a2f960bd0f",
             subject: "Saboteur::MutationSource::RegexReplacement#scan_anchors_and_quantifiers",
             reason: "equivalent: != differs from < only if index skips past bytes.size, which the 1-or-2 step plus the no-trailing-backslash invariant makes unreachable"

  i.mutation "2618574857fdc8c1",
             subject: "Saboteur::MutationSource::RegexReplacement#plain_quantifier?",
             reason: "equivalent: a regex beginning with a quantifier is a RegexpError (target of repeat operator is not specified), and only parsed regexes reach the scanner, so index.zero? never fires"

  i.mutation "4cde174a623048a8",
             subject: "Saboteur::Engine::Scheduler#retried_in_defined_order",
             reason: "equivalent: covered_by entries are non-nil test id strings, so all? is true exactly when any? is " \
                     "unless the array is empty; and an empty covered_by makes DefinedOrderPrefix#for return nil (empty " \
                     "prefix equals empty covering set), so no retry happens either way"
  i.mutation "a8d5b6b2a673a435",
             subject: "Saboteur::Engine::Scheduler#retried_in_defined_order",
             reason: "equivalent: an empty covered_by makes DefinedOrderPrefix#for return nil (the empty prefix equals the " \
                     "empty covering set), so the guard conjunct never changes whether a retry happens"
  i.mutation "8806b9ad93a5145f",
             subject: "Saboteur::Engine::Scheduler#retried_in_defined_order",
             reason: "equivalent: Scheduler#reuse never sets rejected_kill: true, so no reused result can pass the first " \
                     "conjunct and reach the retry"
  i.mutation "056fa35add185fd9",
             subject: "Saboteur::Engine::Scheduler#rerun_in_prefix",
             reason: "equivalent: budget_capped clamps the retry timeout to <= the full one, so < and != agree on every " \
                     "reachable value"

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

  i.mutation "485c590681bcde38",
             subject: "Saboteur::Selection::CoverageMap#files_for",
             reason: "equivalent: nothing mutates the coverage map after construction, so recomputing " \
                     "invert_coverage on every call yields the identical hash the memo would have returned"

  i.mutation "c426c783724e596f",
             subject: "Saboteur::Selection::CoverageMap#invert_coverage",
             reason: "equivalent: the block's acc-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

  i.mutation "52e4bb172b350bc9",
             subject: "Saboteur::Selection::CoverageMap#invert_coverage",
             reason: "equivalent: the block's acc-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

  i.mutation "e2ab34c9185bc8b1",
             subject: "Saboteur::Preview#estimated_seconds",
             reason: "equivalent: work_seconds rescues StandardError and returns nil, so calling it with a nil map " \
                     "yields nil exactly like the && guard"

  i.mutation "53b1c800a4bd394d",
             subject: "Saboteur::Preview#source_span",
             reason: "equivalent: an in-range two-arg byteslice is already a String, so .to_s only matters for " \
                     "the out-of-range nil that in-range edits never produce"
  i.mutation "b555c2d28d9c78cf",
             subject: "Saboteur::ConstantSubjectFinder#owner_path",
             reason: "equivalent: with empty nesting the loop never runs and the trailing parts.empty? returns nil " \
                     "identically; the early return is a fast path, not behavior (10-fixture probe, no divergence)"

  i.mutation "736552442b711990",
             subject: "Saboteur::ConstantSubjectFinder#walk_singleton_class",
             reason: "equivalent: a singleton scope's path is never read - Scope#header returns the literal " \
                     "'class << self', owner_path branches on the sclass? kind, and the reevaluator resolves via " \
                     "singleton_class - so the string surfaces in no output (10-fixture probe, no divergence)"

  i.mutation "b02e8e86ab88faa3",
             subject: "Saboteur::ConstantSubjectFinder#owner_path",
             reason: "equivalent (unreachable): keyword classes and nested factories reject factories from the " \
                     "nesting, so a factory scope is always last or followed only by one singleton scope; after " \
                     "the singleton branch consumes factory_path no later iteration can read the stale value " \
                     "(10-fixture probe over factory/sclass/keyword shapes, no divergence)"

  i.mutation "f03123ea505a2c88",
             subject: "Saboteur::ConstantSubjectFinder#owner_path",
             reason: "equivalent (unreachable): factory_path is non-nil only immediately after a factory scope, " \
                     "and a plain class/module scope never follows a factory in the nesting (lexical_nesting " \
                     "rejects factories), so the plain branch always sees nil (10-fixture probe, no divergence)"

  i.mutation "f86ef657e4210d26",
             subject: "Saboteur::ConstantSubjectFinder#owner_path",
             reason: "equivalent: a factory scope is built only from a ConstantWriteNode name, which never carries " \
                     "a leading ::, so delete_prefix(\"::\") on its path removes nothing (probed: ::X = Class.new is " \
                     "not a factory scope and the mutant survives every spec)"

  i.mutation "b1adadf512cb59eb",
             subject: "Saboteur::Reporter::Terminal#status_line",
             reason: "equivalent: rejected is a count (never negative) and the line is reached only when " \
                     "rejected.positive?, so rejected > 1 and rejected != 1 agree on every reachable value"

  i.mutation "8bfe1be557e2b75f",
             subject: "Saboteur::Selection::DependencyShield#bundler_path",
             reason: "equivalent: an empty value expands to the project root (File.expand_path(\"\", base)), " \
                     "so the expanded == base return two lines later yields the same nil the early return did"

  i.mutation "564f54594f1c2428",
             subject: "Saboteur::Selection::DependencyShield#bundler_path",
             reason: "equivalent: when expanded == base, expanded never starts with \"\#{base}/\", so the " \
                     "!start_with? disjunct already returns on exactly the inputs this comparison covered"

  i.mutation "ced239d4dcdd786a",
             subject: "Saboteur::Selection::DependencyShield#bundler_path",
             reason: "equivalent: the dropped == base disjunct is redundant - base never starts with " \
                     "\"\#{base}/\", so the remaining !start_with? disjunct fires on the same inputs"

  i.mutation "4af40140fd3e6e17",
             subject: "Saboteur::Selection::DependencyShield#strip_comment",
             reason: "equivalent: the include? guard ensures the value contains #, and split's first element " \
                     "is the text before the first # for any positive limit, so .first is invariant"

  i.mutation "afba0fd1ccf31ad9",
             subject: "Saboteur::Selection::DependencyShield#strip_comment",
             reason: "equivalent: limit 0 splits every field like no limit at all, and .first is still the " \
                     "text before the first # under the include? guard"

  i.mutation "517fd716d4c51104",
             subject: "Saboteur::Selection::DependencyShield#strip_comment",
             reason: "equivalent: split without a limit differs from limit 2 only in fields after the " \
                     "first, and .first is identical under the include? guard"

  i.mutation "af0bf54f269aa87b",
             subject: "Saboteur::Engine::RunBudget#refuse_unaffordable_coverage_build",
             reason: "equivalent: dropping the per_pass <= 0 arm changes no outcome - with per_pass <= 0 " \
                     "and remaining > 0 the next guard (remaining >= per_pass) admits identically, and " \
                     "remaining <= 0 is the other arm's case; probed byte-identical admit/refuse on a " \
                     "24-case matrix (2 configs x 2 baseline elapsed x 2 pass counts x 3 run starts)"

  i.mutation "b368e4a7a0b64d06",
             subject: "Saboteur::Engine::RunBudget#refuse_unaffordable_coverage_build",
             reason: "equivalent: per_pass <= 0 fires only at exactly 0.0 (an untimed baseline), where " \
                     "per_pass < 0 is never true, and with remaining > 0 the remaining >= per_pass guard " \
                     "admits identically either way"

  i.mutation "3ce3a72baba4cfff",
             subject: "Saboteur::Engine::RunBudget#refuse_unaffordable_coverage_build",
             reason: "equivalent only via the call path: Engine#mutate always passes " \
                     "guard.completed_passes from check_baseline, an Integer, where to_i is identity; " \
                     "a direct call with nil diverges (nil.to_i.zero? admits, nil.zero? raises " \
                     "NoMethodError), and no caller produces it"

  i.mutation "dee396e30de4b83f",
             subject: "Saboteur::Engine::RunBudget#refuse_unaffordable_coverage_build",
             reason: "equivalent: per_pass is baseline_elapsed / completed_passes and never negative, " \
                     "so <= 0 and == 0 differ only below 0, and at exactly 0.0 both fire; the 24-case " \
                     "admit/refuse probe matrix is byte-identical"

  i.mutation "feb1f2b67bea9964",
             subject: "Saboteur::Engine::RunBudget#refuse_unaffordable_coverage_build",
             reason: "equivalent: per_pass is never negative, so per_pass <= -1 never fires, and at " \
                     "per_pass == 0.0 the remaining >= per_pass guard admits identically; the 24-case " \
                     "admit/refuse probe matrix is byte-identical"

  i.mutation "d774d9400d9f0aa8",
             subject: "Saboteur::Engine::ResultCache#hash_dependency_inputs",
             reason: "equivalent: the block's digest-append side effects are the whole behavior and the " \
                     "enumerator's return value is unused, so each and map agree"

  i.mutation "b61a13a92e68bd24",
             subject: "Saboteur::Engine::ResultCache#dependency_files",
             reason: "equivalent: dropping the slash from the stripped prefix only adds a leading empty element " \
                     "to the split parts, and no excluded directory name is empty, so the exclusion verdict is " \
                     "identical for every path (probed against the full result_cache specs, no divergence)"

  i.mutation "11b190d63c635f90",
             subject: "Saboteur::Engine::TestGuess#covered_by_changed_specs",
             reason: "equivalent: without the early return, an empty unmatched list selects nothing and an empty " \
                     "changed_specs list gives ConstantReads.across([], constant) == {}, so the result is [] either way; " \
                     "defined_constants only differs by raising on a missing file, and unmatched files exist"

  i.mutation "c84c07e7e026ce01",
             subject: "Saboteur::Engine::TestGuess#covered_by_changed_specs",
             reason: "equivalent: dropping the changed_specs.empty? check leaves an empty spec list, and " \
                     "ConstantReads.across([], constant) is {}, so no unmatched file is selected and the result is []"

  i.mutation "de12f60cceeac84d",
             subject: "Saboteur::Engine::TestGuess#covered_by_changed_specs",
             reason: "equivalent: dropping the unmatched.empty? check leaves select running on an empty list, " \
                     "which returns [] exactly like the early return"

  i.mutation "18a3dccbcb3e3f87",
             subject: "Saboteur::CLI::SurvivorsBrowser#all_survivors",
             reason: "equivalent: the memoized list is a pure function of @report, so dropping ||= for = only " \
                     "recomputes the same value on repeat calls - hand-applied mutant leaves all 16 browser " \
                     "pin examples green"

  i.mutation "25001e3b3f1acb36",
             subject: "Saboteur::CLI::SurvivorsBrowser#findings_by_digest",
             reason: "equivalent: the memoized index is a pure function of @findings, so dropping ||= for = only " \
                     "recomputes the same value on repeat calls - hand-applied mutant leaves all 16 browser " \
                     "pin examples green"

  i.mutation "8bc1d296bb4eea51",
             subject: "Saboteur::CLI::SurvivorsBrowser#original_line",
             reason: "equivalent on reachable inputs: the report entry's source is always a String and " \
                     "String#to_s is identity - hand-applied mutant leaves all 16 browser pin examples green"

  i.mutation "8cf9af2d9d2832d2",
             subject: "Saboteur::CLI::SurvivorsBrowser#original_line",
             reason: "equivalent on reachable inputs: the mutant's line always exists in the same entry's " \
                     "source (both come from one report entry), so lines[i] is a String and its to_s is " \
                     "identity - hand-applied mutant leaves all 16 browser pin examples green"

  i.mutation "49370ec53fcedd1f",
             subject: "Saboteur::CLI::SurvivorsBrowser#ranked_order",
             reason: "digest is the final tie-break of the ranked sort key and only decides under a full " \
                     "[rank, -coverage, path, line] tie; removing it leaves equal keys whose order Ruby's " \
                     "sort_by leaves unspecified, which no deterministic spec can pin - hand-applied mutant " \
                     "leaves all 16 browser pin examples green"

  i.mutation "9561b9b71f0ba7a2",
             subject: "Saboteur::Engine::BaselineGuard#warn_minitest_signature",
             reason: "equivalent on reachable inputs: errors.empty? returns before pluralization at zero; " \
                     "errors.size is therefore an Integer >= 1, where > 1 and != 1 agree. " \
                     "Hand-applied mutant passes exact full-warning assertions for one and two errors"

  i.mutation "9025a0a9913047a1",
             subject: "Saboteur::Integration::RSpec::SetupOutputCapture#puts",
             reason: "equivalent: Array#join flattens nested arrays recursively and honors to_ary identically " \
                     "to Array#flatten; identical output for every reachable puts argument"

  i.mutation "800f2696b862dbb5",
             subject: "Saboteur::Execution::Reevaluator#eval_whole_file",
             reason: "equivalent: Ruby require membership-checks expanded paths, so a duplicate " \
                     "$LOADED_FEATURES entry is inert; always-append never reloads the file"
  # #338 subject.rb slice: the chain cuts below are byte-identical because
  # Prism::Node#start_offset / #end_offset / #start_line delegate to the
  # location (probed on Prism 1.9.0), same precedent as 41623d58ed9d06c8.
  i.mutation "24bcc50d50f58ded",
             subject: "Saboteur::Subject#innermost_statement",
             reason: "equivalent: Prism::Node#start_offset delegates to location.start_offset (probed), " \
                     "so the chain cut is identical"
  i.mutation "5fe7685e70b3d92d",
             subject: "Saboteur::Subject#innermost_statement",
             reason: "equivalent: Prism::Node#end_offset delegates to location.end_offset (probed), " \
                     "so the chain cut is identical"
  i.mutation "a337833011bd6c56",
             subject: "Saboteur::Subject#innermost_statement",
             reason: "equivalent: Prism::Node#start_offset delegates to location.start_offset (probed), " \
                     "so the chain cut is identical"
  i.mutation "a56139b006e5cc80",
             subject: "Saboteur::Subject#innermost_statement",
             reason: "equivalent: Prism::Node#end_offset delegates to location.end_offset (probed), " \
                     "so the chain cut is identical"

  i.mutation "4d7ee1a553233ee6",
             subject: "Saboteur::Subject#innermost_statement",
             reason: "equivalent: among StatementsNode children only the found statement fully contains " \
                     "the edit, so the else-loop recurses into it whether or not node was reassigned; " \
                     "the assignment also fed the embedded flag, and a method-body statement is never " \
                     "an EmbeddedStatementsNode (interpolation bodies sit inside EmbeddedNode parts), " \
                     "so the flag agrees - replayed and survives"

  i.mutation "f6ca28570a86f500",
             subject: "Saboteur::Engine::TestGuess#unique_suffix_spec",
             reason: "equivalent under the one? guard: matches holds exactly one element when " \
                     "first is evaluated, so first and last agree - hand-applied mutant passes " \
                     "all 144 test_guess_spec examples"

  i.mutation "79a615dba02c8a27",
             subject: "Saboteur::Engine::TestGuess#unique_suffix_spec",
             reason: "equivalent with a nil pack: interpolating nil makes the branch " \
                     "'/spec', and File.join(@root, '/spec', ...) joins to the same path " \
                     "as 'spec' - hand-applied mutant passes all 144 test_guess_spec examples"
  i.mutation "e03f49bead1413b5",
             subject: "Saboteur::MutationSource::ArgumentSwap#mutate_node",
             reason: "equivalent for Prism nodes: Node#start_offset delegates to location.start_offset, " \
                     "so removing .location constructs the same byte-range edit"

  i.mutation "76a68daf2dc3ee7a",
             subject: "Saboteur::MutationSource::ArgumentSwap#mutate_node",
             reason: "equivalent for Prism nodes: Node#end_offset delegates to location.end_offset, " \
                     "so removing .location constructs the same byte-range edit"

  i.mutation "be3a75c7143053e0",
             subject: "Saboteur::MutationSource::ArgumentSwap#heredoc?",
             reason: "equivalent on visited argument ASTs: text starting with << is a heredoc opener, " \
                     "so node.slice and opening_loc.slice agree on this prefix; nil versus false is " \
                     "consumed by || before recursion. Probed ordinary, operator, nested and heredoc arguments"

  i.mutation "eb1652880a85f857",
             subject: "Saboteur::Reporter::Terminal#warnings",
             reason: "equivalent: the each result is discarded - call(report) runs warnings(report) for " \
                     "its puts effect, so each and map run the same body; hand-applied mutant leaves " \
                     "all 80 terminal_spec examples green"
  i.mutation "5026bbf067f91fad",
             subject: "Saboteur::Reporter::Terminal#test_command_gaps",
             reason: "equivalent: the block's @out.puts side effects are the whole behavior and the " \
                     "group_by enumerator's return value is unused, so each and map agree - hand-applied " \
                     "mutant leaves all 558 reporter and subject_finder examples green"

  i.mutation "374ebee170d105b5",
             subject: "Saboteur::SubjectFinder#report_receiver_def",
             reason: "equivalent: Subject.new's sig_span keyword already defaults to nil (subject.rb:43), " \
                     "so restating it changes nothing (Pod 1 verified at v2) - hand-applied mutant leaves " \
                     "all 558 reporter and subject_finder examples green"

i.mutation "fdc4600f4e8e8625",
             subject: "Saboteur::CustomMap.validate_spec",
             reason: "equivalent: with the root check above the numbered && named guard (#712), " \
                     "numbered = key.is_a?(Regexp) only moves which branch runs - outside-root " \
                     "templates raise the root error before either form diverges, named templates " \
                     "raise the same backreferences error at either raise site - a 10-case probe (plain, numbered, named and mixed templates, inside and outside the root, plus String-keyed backref-marker cases) prints identical outcomes for original and mutant"

  i.mutation "9fcef196d5c48899",
             subject: "Saboteur::CustomMap.validate_spec",
             reason: "equivalent: numbered = spec.match? widens numbered to String keys carrying a " \
                     "literal backslash-digit, but the root check guards every path first (#712), " \
                     "so such a spec is accepted inside the root and rejected outside it exactly " \
                     "like the original - a 10-case probe (plain, numbered, named and mixed templates, inside and outside the root, plus String-keyed backref-marker cases) prints identical outcomes for original and mutant"

  i.mutation "616bbe561c8b198c",
             subject: "Saboteur::CustomMap.validate_spec",
             reason: "equivalent: numbered = false drops the backreference early return, but the " \
                     "root check guards every path first (#712) and named is false wherever " \
                     "numbered could have been true alone, so the method returns or raises the " \
                     "same ConfigError with the same message - a 10-case probe (plain, numbered, named and mixed templates, inside and outside the root, plus String-keyed backref-marker cases) prints identical outcomes for original and mutant"

  i.mutation "ffdffbe395900a87",
             subject: "Saboteur::CustomMap.validate_spec",
             reason: "equivalent: when named is true the guard reading bare named instead of " \
                     "numbered && named raises the same ConfigError with the same message at :79 " \
                     "instead of the method end - a 10-case probe (plain, numbered, named and mixed templates, inside and outside the root, plus String-keyed backref-marker cases) prints identical outcomes for original and mutant"

  i.mutation "a5d10e356957ec9f",
             subject: "Saboteur::CustomMap.validate_spec",
             reason: "equivalent: return if false removes the backreference early return; an " \
                     "in-root backref spec then reaches return unless named with named false and " \
                     "returns without error just the same, and an outside-root one already raised " \
                     "- a 10-case probe (plain, numbered, named and mixed templates, inside and outside the root, plus String-keyed backref-marker cases) prints identical outcomes for original and mutant"

  # test_command_shape.rb:62 - String#split treats every negative limit the same: no
  # truncation, trailing empty fields kept. The pinned quoted-semicolon example expects
  # the trailing empty segment, so -1 and -2 produce identical segments.
  i.mutation "0f7ff6bcc042e45b",
             subject: "Saboteur::Execution::TestCommandShape#semicolon_segments",
             reason: "equivalent: split(\";\", -2) still means no limit with trailing " \
                     "empties kept (any negative limit behaves alike); the trailing-empty " \
                     "pin in the spec stays green either way"

  # test_command_shape.rb:70 - `token == "-e"` is fully covered by the adjacent
  # `token.start_with?("-e")` disjunct, so any mutation of the equality arm leaves the
  # -e guard unchanged for every token.
  i.mutation "d942e3ccba0e9966",
             subject: "Saboteur::Execution::TestCommandShape#ruby_multi_file_simple_command?",
             reason: "equivalent: dropping the `token == \"-e\"` arm leaves " \
                     "start_with?(\"-e\"), which is true for \"-e\" itself - the guard " \
                     "rejects the same tokens"
  i.mutation "f2ba2275de6bc416",
             subject: "Saboteur::Execution::TestCommandShape#ruby_multi_file_simple_command?",
             reason: "equivalent: `token == \"-e\"` -> false reduces the disjunction to " \
                     "start_with?(\"-e\"), which covers the equality case - same tokens " \
                     "rejected"

  # external_runner.rb:258 - the absolute original is interpolated into the copy root via
  # File.join; File.join(root, "/engines/x") and File.join(root, "engines/x") are the same
  # path, and expanded always sits under the root here, so delete_prefix without the slash
  # leaves a leading / that File.join treats identically. Hand-applied mutant: all 67
  # external_runner examples green on merged main 28162ddb.
  i.mutation "1e1a7126fb3759c3",
             subject: "Saboteur::Execution::ExternalRunner#rebase_path_sources",
             reason: "equivalent: dropping the slash from delete_prefix leaves a leading / " \
                     "on expanded, and File.join(@copy_root, '/engines/x') is the same path " \
                     "as File.join(@copy_root, 'engines/x') - hand-applied mutant leaves " \
                     "all 67 external_runner examples green"

  # external_runner.rb:288 - the "" entry the filter drops can never arise: the ternary
  # already maps expanded == @root to ".", and a realpath'd expanded never equals "/" with
  # the trailing slash. Hand-applied mutant: all 67 external_runner examples green on
  # merged main 28162ddb.
  i.mutation "67f751c4a3f3eec7",
             subject: "Saboteur::Execution::ExternalRunner#rewrite_lockfile_source",
             reason: "equivalent: the \"\" entry the filter drops can never arise - the " \
                     "ternary already maps expanded == @root to \".\", and a realpath'd " \
                     "expanded never equals \"/\" with the trailing slash - hand-applied " \
                     "mutant leaves all 67 external_runner examples green"

  # external_runner.rb:288 - dropping the - [""] filter cannot change the scan: "" never
  # arises (see 67f751c4). A root source spelled "." does duplicate the "." entry, but the
  # surviving .uniq removes it, and even without dedup a duplicated regex alternation
  # matches the same strings. Hand-applied mutant: all 67 external_runner examples green
  # on merged main 28162ddb.
  i.mutation "8d4064cbcc14c141",
             subject: "Saboteur::Execution::ExternalRunner#rewrite_lockfile_source",
             reason: "equivalent: dropping the - [\"\"] filter cannot change the scan - " \
                     "\"\" never arises (the ternary maps expanded == @root to \".\"); " \
                     "a root source spelled \".\" can duplicate the \".\" entry, but the " \
                     "surviving .uniq removes it, and even without dedup a duplicated " \
                     "regex alternation matches the same strings - hand-applied mutant " \
                     "leaves all 67 external_runner examples green"

  # external_runner.rb:257 - the block's return value is discarded: rebase_path_sources
  # iterates for side effects only, and Array#map visits the same pairs in the same
  # order as Array#each. Hand-applied mutant: all 67 external_runner examples green on
  # merged main 28162ddb.
  i.mutation "35143ffa0853a1c4",
             subject: "Saboteur::Execution::ExternalRunner#rebase_path_sources",
             reason: "equivalent: the block's return value is discarded - " \
                     "rebase_path_sources iterates for side effects only - and Array#map " \
                     "visits the same pairs in the same order as Array#each - " \
                     "hand-applied mutant leaves all 67 external_runner examples green"

  # The opts.on name/description swaps below are equivalent: OptionParser::Switch
  # classifies string arguments by content (a leading "--" marks the option name,
  # any other string is a description), not by position, so swapping the two
  # strings builds the identical switch - same parse behavior and same summarize
  # output. Each mutant was hand-applied: all 24 run_option_modules examples green.

  # explicit_file_options.rb:11 - --test PATH / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "46ec300d31b61151",
             subject: "Saboteur::CLI::ExplicitFileOptions#define_explicit_file_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # matrix_option.rb:11 - --matrix / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "adda773c0b4f783d",
             subject: "Saboteur::CLI::MatrixOption#define_matrix_option",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # output_options.rb:11 - --score-history PATH / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "28f9a997ce83a3db",
             subject: "Saboteur::CLI::OutputOptions#define_output_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # output_options.rb:12 - --json PATH / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "d93a180da1d29cf1",
             subject: "Saboteur::CLI::OutputOptions#define_output_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # output_options.rb:13 - --html PATH / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "9cb13c518c18b378",
             subject: "Saboteur::CLI::OutputOptions#define_output_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # output_options.rb:15 - --agent / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "6e78cd0a9b5a9bee",
             subject: "Saboteur::CLI::OutputOptions#define_output_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # output_options.rb:21 - --[no-]color / description swap: OptionParser::Switch classifies string
  # arguments by content, not position, so the swapped call builds the identical
  # switch. Hand-applied mutant: all 24 run_option_modules examples green.
  i.mutation "289f57b681bc8b12",
             subject: "Saboteur::CLI::OutputOptions#define_output_options",
             reason: "equivalent: OptionParser::Switch classifies string arguments by " \
                     "content, not position - swapping the option name and " \
                     "description strings builds the identical switch - " \
                     "hand-applied mutant leaves all 24 run_option_modules " \
                     "examples green"

  # agent_provenance.rb:54 - any? vs all? is equivalent here: @sources is nil or a
  # non-empty array of path strings (use_explicit_sources returns before assigning
  # when argv is empty), and every element is truthy, so any? and all? agree on
  # every reachable value. Hand-applied mutant: all 12 agent_provenance examples
  # green on b-334-provenance 93dd7ccd.
  i.mutation "bca4f4f255fa33d1",
             subject: "Saboteur::CLI::AgentProvenance#agent_mode",
             reason: "equivalent: @sources is nil or a non-empty array of path " \
                     "strings - use_explicit_sources returns before assigning when " \
                     "argv is empty - and every element is truthy, so any? and all? " \
                     "agree on every reachable value - hand-applied mutant leaves " \
                     "all 12 agent_provenance examples green"
  i.mutation "78ef1d693e21db45",
             subject: "Saboteur::Selection::CoverageMap.combine_tests",
             reason: "equivalent: Array#tally only emits counts of 1 or more, so count > 1 and " \
                     "count != 1 agree on every input - hand-applied mutant leaves " \
                     "all 70 coverage_map examples green"

  i.mutation "2b0d2e7470854410",
             subject: "Saboteur::Selection::CoverageMap.combine_hits",
             reason: "equivalent: the each result is discarded (acc is mutated for effect); " \
                     "each and map run the same body - hand-applied mutant leaves " \
                     "all 70 coverage_map examples green"

  i.mutation "9c92542e3d5e8c07",
             subject: "Saboteur::Selection::CoverageMap.combine_hits",
             reason: "equivalent: the each result is discarded (target is mutated for effect); " \
                     "each and map run the same body - hand-applied mutant leaves " \
                     "all 70 coverage_map examples green"

  i.mutation "1aea04b4ad2b5797",
             subject: "Saboteur::Selection::CoverageMap.combine_lists",
             reason: "equivalent: the each result is discarded (acc is mutated for effect); " \
                     "each and map run the same body - hand-applied mutant leaves " \
                     "all 70 coverage_map examples green"

  i.mutation "4a03618cb8cf293d",
             subject: "Saboteur::Execution::SupervisorBatch#reap_started",
             reason: "equivalent: each and map run the same block for its contain " \
                     "side effects; the result is unused - hand-applied mutant " \
                     "leaves all 14 run_many examples green"

  i.mutation "5832856abbec07b5",
             subject: "Saboteur::Execution::SupervisorBatch#reap_started",
             reason: "equivalent: a contain deadline of -1, 0 or 1 second only " \
                     "changes how soon contain starts its terminate; every child is " \
                     "already killed first and reaped either way - hand-applied " \
                     "mutant leaves all 14 run_many examples green"

  i.mutation "f87be5407d5c0b29",
             subject: "Saboteur::Execution::SupervisorBatch#reap_started",
             reason: "equivalent: a contain deadline of -1, 0 or 1 second only " \
                     "changes how soon contain starts its terminate; every child is " \
                     "already killed first and reaped either way - hand-applied " \
                     "mutant leaves all 14 run_many examples green"

  i.mutation "0b52736c7cda4d11",
             subject: "Saboteur::Engine::Scheduler#execute",
             reason: "equivalent: plan.killers only orders tests by kill count in Scheduler.prioritize, " \
                     "and counting each kill as 2 keeps every comparison the same"

  i.mutation "0f936f408a58ca61",
             subject: "Saboteur::Engine::ResultCache#digest_tests",
             reason: "equivalent: the LOCKFILES block appends to the digest as a side effect and " \
                     "digest_tests' return value is unused, so each and map agree"

  i.mutation "4eed968b7a1035f9",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1, 1) holds one frame, so first and last are the same frame"

  i.mutation "d76b6c974576b095",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1, 2).first is the same frame as caller_locations(1, 1).first"

  i.mutation "936bc9297892bfcb",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1) starts at the same frame, so its first element is " \
                     "the same as caller_locations(1, 1).first"

  i.mutation "f1d535ff37ca4bc6",
             subject: "Saboteur::IgnoreList::Collector#mutation",
             reason: "equivalent: caller_locations(1) starts at the same frame, so its first element is " \
                     "the same as caller_locations(1, 1).first"

  i.mutation "33d90de31c1d4d8e",
             subject: "Saboteur::Selection::Recorder#record_branches",
             reason: "equivalent: each_hit calls record_branches for its yields and discards the return value, " \
                     "so each and map visit the same branches and yield the same spans"
  i.mutation "c2417f318e67f647",
             subject: "Saboteur::Selection::Recorder#record_branches",
             reason: "equivalent: the return value of the arm loop is the return value of the branch loop's " \
                     "block, which each discards, so each and map yield the same spans"
  i.mutation "2fcca6d71828298a",
             subject: "Saboteur::Reporter::ReviewComments.place",
             reason: "equivalent: posts only grows by one per pass and the loop stops when it reaches room, " \
                     "so posts.size is never above room and >= and == stop at the same iteration"

  i.mutation "87fc46488069845b",
             subject: "Saboteur::MethodCalls#enable",
             reason: "equivalent: TracePoint#enable on an already enabled tracepoint is a no-op, so skipping the enabled? check never changes the state"

  i.mutation "897010b2f5594c0c",
             subject: "Saboteur::MethodCalls#disable",
             reason: "equivalent: TracePoint#disable on a disabled tracepoint is a no-op, so always disabling never changes the state"
  i.mutation "79b0ad2bc1178eb6",
             subject: "Saboteur::Engine::LoadCoverage.one_line_defs",
             reason: "equivalent: Prism::Node#start_line delegates to location.start_line in the prism 1.x the gemspec requires, so dropping .location reads the same line"

  i.mutation "f086d50c32fbf02a",
             subject: "Saboteur::Engine::LoadCoverage.one_line_defs",
             reason: "equivalent: Prism::Node#end_line delegates to location.end_line in the prism 1.x the gemspec requires, so dropping .location reads the same line"

  i.mutation "758245efed081451",
             subject: "Saboteur::Engine::LoadCoverage.one_line_defs",
             reason: "equivalent: Prism::Node#start_line delegates to location.start_line in the prism 1.x the gemspec requires, so dropping .location reads the same line"

  i.mutation "98684baa2d17a991",
             subject: "Saboteur::Engine::LoadCoverage.one_line_defs",
             reason: "equivalent: the walk lambda is called for its side effect on found; the return value of compact_child_nodes.each is unused, so each and map visit the same nodes"

  i.mutation "1d01461d9f530d5b",
             subject: "Saboteur::Engine::LoadCoverage.boot_calls",
             reason: "equivalent: capture reads boot_calls only for files in its own wanted set, so keeping the calls of other files in the result changes nothing it returns"

  i.mutation "1fa4bba99b359d4e",
             subject: "Saboteur::Selection::Recorder#each_hit",
             reason: "equivalent: the return value of the per-file calls loop is unused (the method ends in ensure), so each and map yield the same hits"

  i.mutation "af6eb7e89ce485cc",
             subject: "Saboteur::Selection::Recorder#each_hit",
             reason: "equivalent: the return value of the per-line yield loop is unused, so each and map yield the same hits"

  i.mutation "530028e5c8380483",
             subject: "Saboteur::Execution::WorkerPool#kill_hard",
             reason: "equivalent: the return value of the targets loop is unused by kill_hard's only caller, so each and map signal the same pids"
end
