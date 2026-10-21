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

  # execution_options.rb add_reuse_options: swapping the flag and description strings of
  # --incremental / --resume DIR. OptionParser#on classifies them by shape, so `run --help`
  # stays byte-identical and option parsing and the cli specs stay green.
  i.mutation "cf71877ec03b88cc",
             subject: "Saboteur::CLI::ExecutionOptions#add_reuse_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not " \
                     "position - hand-applied swap on --incremental leaves run --help byte-identical " \
                     "and run_option_modules_spec (25 examples) green"
  i.mutation "def69c8ca8b265f3",
             subject: "Saboteur::CLI::ExecutionOptions#add_reuse_options",
             reason: "equivalent: same opts.on shape-classification swap on --resume DIR - " \
                     "hand-applied mutant leaves run --help byte-identical and parsing unchanged"

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


  i.mutation "ec4d19cb2b5113b8",
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

  i.mutation "b0bb0f4caea86dcc",
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

  i.mutation "eca2fcc5f3c20fcf",
             subject: "Saboteur::Selection::TraceRecorder#each_hit",
             reason: "equivalent: the yielded hits are the whole behavior and the enumerator's return value is unused, so each and map agree"
  i.mutation "184db463a4589ad6",
             subject: "Saboteur::Selection::TraceRecorder#each_hit",
             reason: "equivalent: the yielded hits are the whole behavior and the enumerator's return value is unused, so each and map agree"
  i.mutation "9ced3f133c6fd805",
             subject: "Saboteur::Selection::TraceRecorder#flush_branches",
             reason: "equivalent: the block only appends to a set, and the enumerator's return value is unused, so each and map agree"
  i.mutation "e7601d71a11e749e",
             subject: "Saboteur::Selection::TraceRecorder#flush_branches",
             reason: "equivalent: the block only appends to a set, and the enumerator's return value is unused, so each and map agree"

  i.mutation "10716a0670a966ba",
             subject: "Saboteur::Config#coerce!",
             reason: "equivalent: the loop only assigns into the values hash and its return value is unused, so each and map agree"

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
  i.mutation "cf0d84a92313d8ca",
             subject: "Saboteur::CLI::RunValidation#reject_test_selection_conflicts",
             reason: "equivalent: options[:tests] is nil or a non-empty list of path strings, all truthy, so any? and all? agree"

  i.mutation "8b0ce18b479016a8",
             subject: "Saboteur::CLI::RunValidation#reject_test_selection_conflicts",
             reason: "equivalent: options[:tests] is nil or a non-empty list of path strings, all truthy, so any? and all? agree"
  i.mutation "ced7e6d7fb9a28bb",
             subject: "Saboteur::CLI::ExplicitSources#require_existing_test",
             reason: "equivalent: the pattern is anchored by \\z, so group+ and group* differ only by an empty match at the end of the path, which strips nothing"
  i.mutation "446090f73943b800",
             subject: "Saboteur::CLI::DirtyTreeNotice#warn_dirty_tree",
             reason: "equivalent: Hash#except removes the same keys whatever their order, so swapping :include and :exclude changes nothing"

  i.mutation "af8158ff67b81e2a",
             subject: "Saboteur::Reporter::ReviewComments.plan",
             reason: "equivalent: a negative room and a room of 0 both post nothing, since place stops as soon as posts.size >= room"
  i.mutation "c96ad351c9e3a9ce",
             subject: "Saboteur::Reporter::ReviewComments.plan",
             reason: "equivalent: a negative room and a room of 0 both post nothing, since place stops as soon as posts.size >= room"
  i.mutation "fc08382c0d183aab",
             subject: "Saboteur::Execution::Wrapper.around",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "5c9718db7ac0073c",
             subject: "Saboteur::Execution::Wrapper.around",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "9135d36247576ac6",
             subject: "Saboteur::Execution::Wrapper.around",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "e5144ba60f006991",
             subject: "Saboteur::Execution::Wrapper.around",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "443af6bddb55ae6f",
             subject: "Saboteur::Execution::Wrapper.original_def",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "8ba064ebf6ea937f",
             subject: "Saboteur::Execution::Wrapper.original_def",
             reason: "equivalent: the whole Sorbet signature lookup sits behind rescue StandardError -> nil, so a failure in this expression falls back to the same nil"
  i.mutation "cb8c2d77571a92b6",
             subject: "Saboteur::Execution::GemfilePathSources#canonical_path",
             reason: "equivalent: the loop only ends with current existing (its root or . always does), so the File.exist? ternary always takes the realpath branch"
  i.mutation "569da12d66c97fdc",
             subject: "Saboteur::Execution::GemfilePathSources#resolver_timed_out?",
             reason: "equivalent: the monotonic clock reading equals the deadline only for an instant, so >= and > differ by one tick of a poll loop"
  i.mutation "a10aa86957b3d76a",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so `<` and `!=` agree at every reachable index"
  i.mutation "9d2965d40e8c59a2",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so `<` and `!=` agree at every reachable index"
  i.mutation "6ce2a872cadabfd1",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so `<` and `!=` agree at every reachable index"
  i.mutation "bbd55a67d49899b2",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so `<` and `!=` agree at every reachable index"
  i.mutation "54bca055a81f715a",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so `<` and `!=` agree at every reachable index"
  i.mutation "0b069928bd9541ab",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so an out-of-range side reads nil and a[i] == b[j] is false there, so the dropped bound check changes nothing"
  i.mutation "2847ea5f9b4b2964",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so an out-of-range side reads nil and a[i] == b[j] is false there, so the dropped bound check changes nothing"
  i.mutation "ae45ddbec4dc8886",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: i never exceeds a.size and j never exceeds b.size (each only advances behind its own bound check), and diff lines are Strings, so an out-of-range side reads nil and a[i] == b[j] is false there, so the dropped bound check changes nothing"
  i.mutation "3c67e4c10a73ffab",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: a range end past the last op is clipped by ops[from..to], and every later range starts at or before the last op so it still merges"
  i.mutation "85951f7294c27dca",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: a range end past the last op is clipped by ops[from..to], and every later range starts at or before the last op so it still merges"
  i.mutation "25a71c13d6e0de59",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: ranges arrive sorted, so `to` is never below the previous range end and [to].max equals the max"

  i.mutation "834259d03f636504",
             subject: "Saboteur::CLI::SurvivorsCommand#survivors_command_inner",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `survivors --help` is byte-identical and the cli specs stay green"
  i.mutation "4fdacc67fb85cf7f",
             subject: "Saboteur::CLI::SurvivorsCommand#survivors_command_inner",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `survivors --help` is byte-identical and the cli specs stay green"
  i.mutation "03f7ea8cbca5301a",
             subject: "Saboteur::CLI::SurvivorsCommand#survivors_command_inner",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `survivors --help` is byte-identical and the cli specs stay green"
  i.mutation "95852308b46e49b7",
             subject: "Saboteur::CLI::SurvivorsCommand#survivors_command_inner",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `survivors --help` is byte-identical and the cli specs stay green"
  i.mutation "8c6e874916dae275",
             subject: "Saboteur::CLI::SurvivorsCommand#survivors_command_inner",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `survivors --help` is byte-identical and the cli specs stay green"
  i.mutation "0ff3020f3d37db9c",
             subject: "Saboteur::CLI::HistoryCommand#badge_parser",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry and history_command_spec stays green"
  i.mutation "d64f9f495a2fe0a4",
             subject: "Saboteur::CLI::HistoryCommand#badge_parser",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry and history_command_spec stays green"
  i.mutation "b02794b33ea444c9",
             subject: "Saboteur::CLI::HistoryCommand#badge_parser",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry and history_command_spec stays green"
  i.mutation "049dedea1dbe78d8",
             subject: "Saboteur::CLI::HistoryCommand#trend_parser",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry and history_command_spec stays green"
  i.mutation "4ceb50817c7c9491",
             subject: "Saboteur::CLI::HistoryCommand#latest_pair",
             reason: "equivalent: HistoryReader.comparable? is symmetric in its two records (== on shared keys, both incomplete lists empty, a non-nil policy equal to the other), so swapping them gives the same answer"
  i.mutation "7ac81b045ff23089",
             subject: "Saboteur::Reporter::ScoreHistory#change",
             reason: "equivalent: comparable_policy? is symmetric in previous and current (version == and a non-nil policy equal to the other), so swapping them gives the same answer"
  i.mutation "399d420e5ffb2bc4",
             subject: "Saboteur::Reporter::Stryker.file_entry",
             reason: "equivalent: results are grouped by subject.file, so every result in the group shares one file_source and first and last read the same string"
  i.mutation "e3995f96c7522bc6",
             subject: "Saboteur::Reporter::TestMatrix#tally",
             reason: "equivalent: the each block only mutates @killed and its return value is discarded by tally and its caller"
  i.mutation "16ffc746e0d4332e",
             subject: "Saboteur::Reporter::MutationText#join",
             reason: "equivalent: the picked value is a String for every real edit (byteslice of an in-range span or a non-nil replacement), so String#to_s is the identity"
  i.mutation "cb43bd9a02fb8183",
             subject: "Saboteur::Baseline::Acceptance#validate_binding",
             reason: "equivalent: the each block only mutates the records in place and its return value is discarded"
  i.mutation "f6842ad8620f21c6",
             subject: "Saboteur::Baseline::Acceptance#safe_path",
             reason: "equivalent: File.identical? compares two paths symmetrically"
  i.mutation "1fed1cf42b3cac19",
             subject: "Saboteur::Baseline::Evidence#validate_generation",
             reason: "equivalent: the each block only validates or raises and validate_generation's return value is discarded by its caller"
  i.mutation "58e02a540021e547",
             subject: "Saboteur::Baseline::Manifest#validate_edits",
             reason: "equivalent: the each block only validates or raises and validate_edits's return value is discarded by its caller"
  i.mutation "ea38bb064aa5fd6d",
             subject: "Saboteur::Baseline::Workflow#guard_artifacts",
             reason: "equivalent: the each block only checks or raises and guard_artifacts's return value is discarded by propose and its sibling caller"

  i.mutation "ba5855123c3dddaf",
             subject: "Saboteur::Reporter::Terminal#inline_suppressions",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "809c9c6decf749bc",
             subject: "Saboteur::Reporter::Terminal#skipped_subjects",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "fd5cf2309d9efb13",
             subject: "Saboteur::Reporter::Terminal#outside_the_score",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "5e1367e5c42a42b1",
             subject: "Saboteur::Reporter::Terminal#print_error_lines",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "43191bfa350b8348",
             subject: "Saboteur::Reporter::Terminal#score_split",
             reason: "equivalent: the only callers interpolate the result into a string, and nil interpolates as the empty string"
  i.mutation "0baf9534c7bf1640",
             subject: "Saboteur::Reporter::Terminal#crash_classes",
             reason: "equivalent: the only callers interpolate the result into a string, and nil interpolates as the empty string"
  i.mutation "c1ee768f65ebf04c",
             subject: "Saboteur::Baseline::Identity#edits",
             reason: "equivalent: String#b only retags the encoding, and unpack1(\"H*\") reads the raw bytes either way, so the hex is unchanged"
  i.mutation "edbd47b43c106121",
             subject: "Saboteur::Baseline::Identity#edits",
             reason: "equivalent: String#b only retags the encoding, and unpack1(\"H*\") reads the raw bytes either way, so the hex is unchanged"
  i.mutation "bb7b34ae173b0630",
             subject: "Saboteur::Baseline::Completeness#validate_results",
             reason: "equivalent: the each block only appends to issues and its return value is discarded"
  i.mutation "570cc90a42c23a68",
             subject: "Saboteur::Selection::DependencyShield#reject_trees",
             reason: "equivalent: Array#reject keeps an element only on a falsy block value, so next nil and next false agree"
  i.mutation "8bbfe884410b5836",
             subject: "Saboteur::CLI::RunBudgetOptions#add_run_budget_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - `run --help` is byte-identical and the cli specs stay green"
  i.mutation "16382227e120f03b",
             subject: "Saboteur::CLI::RunBudgetOptions#add_run_budget_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - `run --help` is byte-identical and the cli specs stay green"
  i.mutation "86ba0c49da5c4d32",
             subject: "Saboteur::CLI::ExitStatus#untested_partial?",
             reason: "equivalent: the predicate is only used as `return EXIT_TOOL if predicate`, so nil and false both fall through"
  i.mutation "30dce853088c94af",
             subject: "Saboteur::CLI::ExitStatus#unverifiable_scope?",
             reason: "equivalent: the predicate is only used as `return EXIT_TOOL if predicate`, so nil and false both fall through"
  i.mutation "57408b208d9e9bc5",
             subject: "Saboteur::CLI::ExitStatus#mostly_errored?",
             reason: "equivalent: the predicate is only used as `return EXIT_TOOL if predicate`, so nil and false both fall through"
  i.mutation "9ffd99d047288e4e",
             subject: "Saboteur::CLI::ExitStatus#incomplete_under_threshold?",
             reason: "equivalent: the predicate is only used as `return EXIT_TOOL if predicate`, so nil and false both fall through"

  i.mutation "0d3de3d9184ab3e2",
             subject: "Saboteur::Reporter::SurvivorList#file_section",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "5ab5816644b5e787",
             subject: "Saboteur::Reporter::SurvivorList#lines",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "2791454ea1c7543d",
             subject: "Saboteur::Reporter::SurvivorList#lines",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "80cf72d0082a3787",
             subject: "Saboteur::Reporter::SurvivorList#lines",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "d71f80b2e8128408",
             subject: "Saboteur::Reporter::SurvivorList#evidence_group",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "f6fb40a288aa372f",
             subject: "Saboteur::Reporter::SurvivorList#source_line",
             reason: "equivalent: the line number comes from a mutation of the same file source, so the index is always in range and String#to_s is the identity"
  i.mutation "45c7748dd7e0fe4a",
             subject: "Saboteur::Reporter::Replay#call",
             reason: "equivalent: the each block only writes to @out and its return value is discarded by the caller, so each and map print the same lines"
  i.mutation "5723271d6c56ed70",
             subject: "Saboteur::Reporter::TestMatrix#tally",
             reason: "equivalent: the key half of each @killed entry is never read (redundant? ignores it with _key), only the count of other killers is"
  i.mutation "132600e011983d58",
             subject: "Saboteur::Reporter::TestMatrix#tally",
             reason: "equivalent: the key half of each @killed entry is never read (redundant? ignores it with _key), only the count of other killers is"

  i.mutation "7761b06158843cf0",
             subject: "Saboteur::ConfigFile#load",
             reason: "equivalent: NoMethodError#name is always a Symbol and Symbol#end_with? exists, so dropping to_s leaves the check unchanged"
  i.mutation "2d4981c342dfb549",
             subject: "Saboteur::CustomMap#duplicate_keys",
             reason: "equivalent: every counted key was incremented at least once from a default of 0, so count != 1 and count > 1 select the same keys"
  i.mutation "96e60c0014af780d",
             subject: "Saboteur::CustomMap#glob_entry",
             reason: "equivalent: the check before it raises unless best.size is 1, so first and last are the same element"

  i.mutation "aca43ebc0c2b0b21",
             subject: "Saboteur::BaselineHealth#exit_detail",
             reason: "equivalent: exit_detail is only interpolated into the baseline failure message, and nil interpolates as the empty string"

  i.mutation "a88dc20d74ab536f",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"
  i.mutation "9516052cab9409d5",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"
  i.mutation "6c28bf0f380a0c44",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"
  i.mutation "87ef9ef4ee7c0fb3",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"
  i.mutation "355e476e76941ff6",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"
  i.mutation "043ca90766f31ed6",
             subject: "Saboteur::CLI::SelectionOptions#define_selection_options",
             reason: "equivalent: OptionParser#on classifies flag vs help strings by shape, not position - the swapped call builds the identical parser entry; `run --help` is byte-identical and the selection specs stay green"

  i.mutation "d36f6a7ad221979b",
             subject: "Saboteur::ConstantReads#bare_match?",
             reason: "equivalent: bare_match? is only used as the last operand of an `if` condition, where nil and false both skip the branch"
  i.mutation "87438bb22e48e90b",
             subject: "Saboteur::MutationSource::ArgumentRemoval#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "744c19ae62b9fe30",
             subject: "Saboteur::MutationSource::ChainRemoval#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "11212cb6092ecf1e",
             subject: "Saboteur::MutationSource::ConditionNegation#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "cfb76cebff6a8978",
             subject: "Saboteur::MutationSource::ArgumentRemoval#separator_for",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "693a8442b31c2809",
             subject: "Saboteur::MutationSource::ArgumentRemoval#separator_for",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "aa024388f862e81e",
             subject: "Saboteur::MutationSource::ArgumentRemoval#separator_for",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "c297dbddc09378c0",
             subject: "Saboteur::MutationSource::ArgumentRemoval#heredoc?",
             reason: "equivalent: a node whose source starts with << is a heredoc or begins with one, and the recursion into its children reaches the heredoc node, so the answer is the same"
  i.mutation "ad72dfe6d7b4d35e",
             subject: "Saboteur::MutationSource::ConstantLiterals#arid?",
             reason: "equivalent: safe_match? with swapped arguments calls String#match?(Regexp) instead of Regexp#match?(String); both raise the same errors on invalid or incompatible bytes and return the same result"

  i.mutation "4eed6578e4dc99d6",
             subject: "Saboteur::MutationSource::EndpointReplacement#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "7ce0ef427a9cac03",
             subject: "Saboteur::MutationSource::FilterReplacement#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "25fa2e0c46682c27",
             subject: "Saboteur::MutationSource::LiteralReplacement#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map builds the same mutations through the same calls"
  i.mutation "60a0e1e2f5e556d0",
             subject: "Saboteur::MutationSource::LiteralReplacement#add",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "447a3ed8248be3de",
             subject: "Saboteur::MutationSource::LiteralReplacement#add",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "5bf452746c03bceb",
             subject: "Saboteur::MutationSource::LiteralReplacement#replace_string",
             reason: "equivalent: a string node's source begins with its opening delimiter, so a heredoc test on node.slice answers the same as one on node.opening_loc.slice"

  i.mutation "971ae38c93e2a3b8",
             subject: "Saboteur::Doctor#check_boot_files",
             reason: "equivalent: the each result is discarded (the method's value is never read), so map runs the same block calls"
  i.mutation "550c0ce0b18291c5",
             subject: "Saboteur::Doctor#check_boot_files",
             reason: "equivalent: the each result is discarded (the method's value is never read), so map runs the same block calls"
  i.mutation "1e13e965a48d47ba",
             subject: "Saboteur::Doctor#check_ignore_subjects",
             reason: "equivalent: the each result is discarded (the method's value is never read), so map runs the same block calls"
  i.mutation "bf6a300278565a5d",
             subject: "Saboteur::MutationSource::OperatorAssignment#visit",
             reason: "equivalent: the each result is discarded (the method's value is never read), so map runs the same block calls"

  i.mutation "a8c04c1601e63d4e",
             subject: "Saboteur::MutationSource::PairRemoval#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map runs the same block calls"
  i.mutation "dea2db8bfbb7a592",
             subject: "Saboteur::MutationSource::PairRemoval#remove_keywords",
             reason: "equivalent: the each result is discarded (remove_keywords' value is never read), so map runs the same block calls"
  i.mutation "d3020e0b03d82ce7",
             subject: "Saboteur::MutationSource::PairRemoval#ending_for",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "fcbf41d9b88105d2",
             subject: "Saboteur::MutationSource::PairRemoval#ending_for",
             reason: "equivalent: Prism nodes expose start_offset and end_offset directly, equal to location.start_offset and location.end_offset"
  i.mutation "a90400c5118a2262",
             subject: "Saboteur::MutationSource::RangeReplacement#visit",
             reason: "equivalent: the each result is discarded (visit's value is never read), so map runs the same block calls"
  i.mutation "cf88d02f3de9135e",
             subject: "Saboteur::MutationSource::RegexReplacement#plain_quantifier?",
             reason: "equivalent: plain_quantifier? is only used as the last operand of an && inside an if modifier, where nil and false both skip the yield"

  i.mutation "9d0ca3c99887dd7b",
             subject: "Saboteur::Engine::CoveragePartial#partial_map",
             reason: "equivalent: stale_specs treats its two snapshots alike - the SAME keys are compared for equality and changed_files needs equal file sets and skips unchanged files, and the result is re-sorted into run order - so swapping base and current gives the same stale list; the 600 coverage store, partial and invalidation specs stay green"

  i.mutation "d1fed205e803f0bf",
             subject: "Saboteur::Engine::CoverageStore#part_map",
             reason: "equivalent: part_map is called only for its refusal and its return value is discarded, so returning nil instead of the map changes nothing"
  i.mutation "e1e8c2b9b39fdca7",
             subject: "Saboteur::Engine::CoverageStore#output_tail",
             reason: "equivalent: output_tail is only interpolated into the build-failure message, and nil interpolates as the empty string"
  i.mutation "032f6f477ac64365",
             subject: "Saboteur::Config#validate_operator_config!",
             reason: "equivalent: the each result is discarded (the method's value is never read), so map compiles the same patterns and raises the same RegexpError"

  i.mutation "8686a6d87dccf107",
             subject: "Saboteur::Baseline::Command#baseline_parser",
             reason: "equivalent: OptionParser#on tells a flag from its description by shape (a leading dash), not by position, so swapping the two string arguments builds the same switch; all five swaps applied together leave baseline --help byte-identical and the baseline and cli specs green (368 examples)"

  i.mutation "c30cbc5e1e04084e",
             subject: "Saboteur::Baseline::Command#baseline_parser",
             reason: "equivalent: OptionParser#on tells a flag from its description by shape (a leading dash), not by position, so swapping the two string arguments builds the same switch; all five swaps applied together leave baseline --help byte-identical and the baseline and cli specs green (368 examples)"

  i.mutation "de60a0cab57b71bd",
             subject: "Saboteur::Baseline::Command#baseline_parser",
             reason: "equivalent: OptionParser#on tells a flag from its description by shape (a leading dash), not by position, so swapping the two string arguments builds the same switch; all five swaps applied together leave baseline --help byte-identical and the baseline and cli specs green (368 examples)"

  i.mutation "02a6322f29c7e609",
             subject: "Saboteur::Baseline::Command#baseline_parser",
             reason: "equivalent: OptionParser#on tells a flag from its description by shape (a leading dash), not by position, so swapping the two string arguments builds the same switch; all five swaps applied together leave baseline --help byte-identical and the baseline and cli specs green (368 examples)"

  i.mutation "d392826fe7cd709a",
             subject: "Saboteur::Baseline::Command#baseline_parser",
             reason: "equivalent: OptionParser#on tells a flag from its description by shape (a leading dash), not by position, so swapping the two string arguments builds the same switch; all five swaps applied together leave baseline --help byte-identical and the baseline and cli specs green (368 examples)"

  # rails.rb: each -> map on three loops whose block value is thrown away (prepare_workers
  # copies, disconnect, restore_memory_databases) and the unused covered_by keyword of scheduler skip_all.
  # Hand-applied together: frameworks and engine specs stay green (1825 and 1738 examples).
  i.mutation "0c9d10255de51547",
             subject: "Saboteur::Frameworks::Rails#prepare_workers",
             reason: "equivalent: the per-worker copy loop is a statement whose value is discarded, so " \
                     "map builds an array nobody reads - hand-applied mutant leaves frameworks and " \
                     "engine specs green"
  i.mutation "b0ce543c8313b41e",
             subject: "Saboteur::Frameworks::Rails#disconnect",
             reason: "equivalent: no caller uses the value of disconnect (every call is a statement or a " \
                     "hook whose result Hooks#run drops), so map instead of each only allocates - " \
                     "hand-applied mutant leaves frameworks and engine specs green"
  i.mutation "cfa542d70c64f441",
             subject: "Saboteur::Frameworks::Rails#restore_memory_databases",
             reason: "equivalent: callers (start_worker, reconnect) ignore the return value, so map " \
                     "instead of each only allocates - hand-applied mutant leaves frameworks and " \
                     "engine specs green"
  i.mutation "bd23029449e69912",
             subject: "Saboteur::Engine::Scheduler.prioritize",
             reason: "equivalent where sort_by Array-key sort is stable (no tie reordering found on ruby " \
                     "3.4.6 Linux x86_64 in 230k random inputs); the index states the contract and is " \
                     "pinned by scheduler_prioritize_ties_spec; macOS unverified"
  i.mutation "11af31c81d6c7e6a",
             subject: "Saboteur::Engine::Scheduler#skip_all",
             reason: "equivalent: no caller passes covered_by, and MutantResult defaults covered_by to " \
                     "the same empty array, so dropping the keyword changes nothing - hand-applied " \
                     "mutant leaves engine specs green"

  # agent.rb Agent.fit and agent_incomplete.rb Incomplete.omitted_by_cap. Hand-applied
  # together: the reporter specs stay green (591 examples).
  i.mutation "a73bc5c9b5daadcb",
             subject: "Saboteur::Reporter::Agent.fit",
             reason: "equivalent: the snippet loop leaves only through the return inside its block, so " \
                     "each versus map differs only by the array map would build when no return fires, " \
                     "and fit then ignores that value - hand-applied mutant leaves reporter specs green"
  i.mutation "2716ff28410c464b",
             subject: "Saboteur::Reporter::Agent::Incomplete.omitted_by_cap",
             reason: "equivalent: with digits present the greedy group captures the same number, and " \
                     "with none it captures an empty string whose to_i is 0, the same as the nil of " \
                     "no match - hand-applied mutant leaves reporter specs green"

  # process_tree.rb grow and stop_until_stable. Hand-applied together: the execution specs,
  # pins included, stay green.
  i.mutation "ed033b0fc0fb0d34",
             subject: "Saboteur::Execution::ProcessTree#grow",
             reason: "equivalent: the select block returns nil instead of false for a known or own pid, " \
                     "and select treats both as falsy - hand-applied mutant leaves execution specs green"
  i.mutation "88a882714af2499c",
             subject: "Saboteur::Execution::ProcessTree#grow",
             reason: "equivalent: the each over the added entries only fills @known and its value is " \
                     "discarded, so map builds an unused array - hand-applied mutant leaves execution " \
                     "specs green"
  i.mutation "b30d25855f36a75e",
             subject: "Saboteur::Execution::ProcessTree#stop_until_stable",
             reason: "equivalent: the each over the fresh entries is the last statement of a times block " \
                     "whose value is discarded, so map builds an unused array - hand-applied mutant " \
                     "leaves execution specs green"
  i.mutation "261e4e0570d18a62",
             subject: "Saboteur::Execution::ProcessTree#stop_until_stable",
             reason: "equivalent: the stopped hash is only read with key?, so the stored value true or " \
                     "false is never looked at - hand-applied mutant leaves execution specs green"

  # shadow_comparison.rb hits: the per-line id sort and the empty-file guard. Hand-applied
  # together: spec/saboteur/engine stays green (1738 examples).
  i.mutation "7fb5bcfe29ad2a88",
             subject: "Saboteur::Engine::ShadowComparison#hits",
             reason: "equivalent: credits compares ids by array subtraction, size and emptiness, none of " \
                     "which depends on id order, so dropping the sort changes no difference found - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "e56448a0de36136d",
             subject: "Saboteur::Engine::ShadowComparison#hits",
             reason: "equivalent: hit_differences reads a missing file as an empty hash, and credits of " \
                     "two empty hashes is zero, so an empty entry and no entry give the same result - " \
                     "hand-applied mutant leaves engine specs green"

  # reporter/diff.rb operations and hunks. Hand-applied together: the reporter specs stay
  # green (591 examples).
  i.mutation "e7b25b4905f420a9",
             subject: "Saboteur::Reporter::Diff#operations",
             reason: "equivalent: j starts at 0 and only grows while it is below b.size, so it never " \
                     "exceeds b.size and j == b.size means the same as j >= b.size - hand-applied " \
                     "mutant leaves reporter specs green"
  i.mutation "1964873e679f491e",
             subject: "Saboteur::Reporter::Diff#hunks",
             reason: "equivalent: ranges are built in ascending order, so the end of the first hunk is " \
                     "never above the new range end and max of the two is always the new end - " \
                     "hand-applied mutant leaves reporter specs green"

  # engine/unchanged_syntax.rb digest and base_subjects, engine/candidates.rb ordering.
  # Hand-applied together: spec/saboteur/engine and selection stay green (2054 examples).
  i.mutation "a9717e10a506fb98",
             subject: "Saboteur::Engine::UnchangedSyntax.digest",
             reason: "equivalent: Prism nodes answer start_line as an alias of location.start_line, so " \
                     "dropping the location hop reads the same number - hand-applied mutant leaves " \
                     "engine specs green"
  i.mutation "1819a12ad9036608",
             subject: "Saboteur::Engine::UnchangedSyntax.digest",
             reason: "equivalent: a digest is compared with the digest of the same field of the same node " \
                     "type, so a one-line __LINE__ entry versus a type and line pair cannot collide " \
                     "with any other digest shape - hand-applied mutant leaves engine specs green"
  i.mutation "1dc5da070e97252d",
             subject: "Saboteur::Engine::UnchangedSyntax#base_subjects",
             reason: "equivalent: keeping the leading slash makes git show read base:.//path, and git " \
                     "resolves that to the same blob as base:./path (same bytes, checked in a scratch " \
                     "repo) - hand-applied mutant leaves engine specs green"
  i.mutation "a29b96b44beaa753",
             subject: "Saboteur::Engine::Candidates#for",
             reason: "equivalent: the key only separates coarse from the rest, so 2 instead of 1 for a " \
                     "non-coarse mutation sorts the same way - hand-applied mutant leaves engine specs green"
  i.mutation "3dedd031b468a504",
             subject: "Saboteur::Engine::Candidates#for",
             reason: "equivalent where the Array-key sort_by keeps ties in order (no tie reorder found " \
                     "on ruby 3.4.6 Linux, macOS unverified); the index states the contract"

  # reporter/html.rb. Hand-applied together: spec/saboteur/reporter stays green (592 examples).
  i.mutation "e733f226babab2ef",
             subject: "Saboteur::Reporter::Html#call",
             reason: "equivalent: the class build is new(nil).build and the instance build reads no " \
                     "instance state, so calling build on self renders the same page - hand-applied " \
                     "mutant leaves reporter specs green"
  i.mutation "d2f58b902fe91c80",
             subject: "Saboteur::Reporter::Html#inline_suppressions",
             reason: "equivalent: the only call site is the heredoc interpolation, where nil renders as " \
                     "an empty string, so return nil instead of an empty string changes no output - " \
                     "hand-applied mutant leaves reporter specs green"
  i.mutation "df4997b189549108",
             subject: "Saboteur::Reporter::Html#warnings",
             reason: "equivalent: the only call site is the heredoc interpolation, where nil renders as " \
                     "an empty string, so return nil instead of an empty string changes no output - " \
                     "hand-applied mutant leaves reporter specs green"
  i.mutation "9939ed43ddb96b76",
             subject: "Saboteur::Reporter::Html#skipped_subjects",
             reason: "equivalent: the only call site is the heredoc interpolation, where nil renders as " \
                     "an empty string, so return nil instead of an empty string changes no output - " \
                     "hand-applied mutant leaves reporter specs green"
  i.mutation "61f9e7ec38ec9d4e",
             subject: "Saboteur::Reporter::Html#change",
             reason: "equivalent: the line is reached only after the return unless edits.size == 1, so " \
                     "edits.first and edits.last are the same edit - hand-applied mutant leaves " \
                     "reporter specs green"

  # engine/bytecode_equivalence.rb, diagnostics.rb and sandbox_policy.rb. Hand-applied together:
  # spec/saboteur/engine stays green (1755 examples).
  i.mutation "b775b9b2e058b4a9",
             subject: "Saboteur::Engine::BytecodeEquivalence#equivalent?",
             reason: "equivalent: exact? answers the same with its two sides swapped, since every " \
                     "branch tests the class of one side against the other and eql? is symmetric - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "50b1a7631fd4ea4b",
             subject: "Saboteur::Engine::BytecodeEquivalence#exact?",
             reason: "equivalent: exact? answers the same with its two sides swapped, since every " \
                     "branch tests the class of one side against the other and eql? is symmetric - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "a648f8079d776bf3",
             subject: "Saboteur::Engine::BytecodeEquivalence#exact?",
             reason: "equivalent: exact? answers the same with its two sides swapped, since every " \
                     "branch tests the class of one side against the other and eql? is symmetric - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "2604081d86a74d6d",
             subject: "Saboteur::Engine::BytecodeEquivalence#strip_positions",
             reason: "equivalent: major, minor, format, name and type are the same for the original " \
                     "and every mutant (one Ruby, one compile, and no operator renames or retypes a " \
                     "method), so leaving one out of the fingerprint changes no comparison - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "0e710ac5f6f07f48",
             subject: "Saboteur::Engine::BytecodeEquivalence#strip_positions",
             reason: "equivalent: major, minor, format, name and type are the same for the original " \
                     "and every mutant (one Ruby, one compile, and no operator renames or retypes a " \
                     "method), so leaving one out of the fingerprint changes no comparison - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "1e0ddbdc8b0765c0",
             subject: "Saboteur::Engine::BytecodeEquivalence#strip_positions",
             reason: "equivalent: major, minor, format, name and type are the same for the original " \
                     "and every mutant (one Ruby, one compile, and no operator renames or retypes a " \
                     "method), so leaving one out of the fingerprint changes no comparison - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "b900a7a48b9e2861",
             subject: "Saboteur::Engine::BytecodeEquivalence#strip_positions",
             reason: "equivalent: major, minor, format, name and type are the same for the original " \
                     "and every mutant (one Ruby, one compile, and no operator renames or retypes a " \
                     "method), so leaving one out of the fingerprint changes no comparison - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "7e1131923f5b3e68",
             subject: "Saboteur::Engine::BytecodeEquivalence#strip_positions",
             reason: "equivalent: major, minor, format, name and type are the same for the original " \
                     "and every mutant (one Ruby, one compile, and no operator renames or retypes a " \
                     "method), so leaving one out of the fingerprint changes no comparison - " \
                     "hand-applied mutant leaves engine specs green"
  i.mutation "dfd095dfa1de939c",
             subject: "Saboteur::Engine::Diagnostics::ProgressHeartbeat#progress_note",
             reason: "equivalent: the only call site interpolates the value into a string, where nil " \
                     "renders as an empty string, so return nil instead of an empty string changes " \
                     "no output - hand-applied mutant leaves engine specs green"
  i.mutation "0357a8e512c4e7e4",
             subject: "Saboteur::Engine::Diagnostics#eta_text",
             reason: "equivalent: the only call site interpolates the value into a string, where nil " \
                     "renders as an empty string, so return nil instead of an empty string changes " \
                     "no output - hand-applied mutant leaves engine specs green"
  i.mutation "727586f907bcd190",
             subject: "Saboteur::Engine::SandboxPolicy#check_sandbox_write_set",
             reason: "equivalent: the each over the user grants only warns and its value is " \
                     "discarded by the last statement of a method whose result is not used, so map " \
                     "builds an unused array - hand-applied mutant leaves engine specs green"

  # subject_selection.rb, coverage_inputs_snapshot.rb and test_guess.rb: nil where false or an
  # empty string was returned. Hand-applied together: spec/saboteur/engine stays green (1755 examples).
  i.mutation "12f6ab4d4a0f722b",
             subject: "Saboteur::Engine::SubjectSelection#constant_note",
             reason: "equivalent: the only caller interpolates the value into a warning string, " \
                     "where nil renders as an empty string, so return nil instead of an empty " \
                     "string changes no output - hand-applied mutant leaves engine specs green"
  i.mutation "511d9206d2d3caf9",
             subject: "Saboteur::Engine::CoverageInputsSnapshot#valid?",
             reason: "equivalent: valid? has one caller, which only tests the result for " \
                     "truthiness, and nil is as falsy as false - hand-applied mutant leaves engine " \
                     "specs green"
  i.mutation "7c236fdabbd5aa88",
             subject: "Saboteur::Engine::CoverageInputsSnapshot#valid?",
             reason: "equivalent: valid? has one caller, which only tests the result for " \
                     "truthiness, and nil is as falsy as false - hand-applied mutant leaves engine " \
                     "specs green"
  i.mutation "3fa6b0e0e72748d7",
             subject: "Saboteur::Engine::CoverageInputsSnapshot#valid?",
             reason: "equivalent: valid? has one caller, which only tests the result for " \
                     "truthiness, and nil is as falsy as false - hand-applied mutant leaves engine " \
                     "specs green"
  i.mutation "55b2be4c53c6f2cb",
             subject: "Saboteur::Engine::CoverageInputsSnapshot#valid?",
             reason: "equivalent: valid? has one caller, which only tests the result for " \
                     "truthiness, and nil is as falsy as false - hand-applied mutant leaves engine " \
                     "specs green"
  i.mutation "8211fb12d7a3e3a3",
             subject: "Saboteur::Engine::CoverageInputsSnapshot#valid?",
             reason: "equivalent: valid? has one caller, which only tests the result for " \
                     "truthiness, and nil is as falsy as false - hand-applied mutant leaves engine " \
                     "specs green"
  i.mutation "f391e781f6b530a2",
             subject: "Saboteur::Engine::TestGuess#effective_subject_files",
             reason: "equivalent: select keeps a file only for a truthy block value, and nil is as " \
                     "falsy as false - hand-applied mutant leaves engine specs green"
  i.mutation "a79b7ddcc3900311",
             subject: "Saboteur::Engine::TestGuess#subjectless_files",
             reason: "equivalent: reject drops a file only for a truthy block value, and nil is as " \
                     "falsy as false - hand-applied mutant leaves engine specs green"
  # baseline_guard.rb, focus_guard.rb and run_fingerprint.rb. Hand-applied together:
  # spec/saboteur/engine, integration and the focus e2e stay green (1849 examples).
  i.mutation "aab1a6168e2d352b",
             subject: "Saboteur::Engine::BaselineGuard#failure_excerpt",
             reason: "equivalent: the only caller interpolates the value into a message, where nil " \
                     "renders as an empty string, so return nil instead of an empty string changes " \
                     "no output - hand-applied mutant leaves the engine, integration and focus e2e " \
                     "specs green"
  i.mutation "58d7f6872f31ebc9",
             subject: "Saboteur::Integration::FocusGuard#check!",
             reason: "equivalent: with no stray focus rule the examples without it are exactly the " \
                     "running examples, so hidden_examples is empty and the next line returns " \
                     "anyway; dropping the early return only does that work first - hand-applied " \
                     "mutant leaves the engine, integration and focus e2e specs green"
  i.mutation "058f10c3854616ea",
             subject: "Saboteur::Engine::RunFingerprint#data_files",
             reason: "equivalent: reject treats a nil block value like false, so next nil instead " \
                     "of next false drops the same files - hand-applied mutant leaves the engine, " \
                     "integration and focus e2e specs green"
  i.mutation "eddcf38c00d91eac",
             subject: "Saboteur::Engine::RunFingerprint#initialize",
             reason: "equivalent: a missing required key reads as true through the fetch default, " \
                     "so leaving required: true out of the entry changes nothing - hand-applied " \
                     "mutant leaves the engine, integration and focus e2e specs green"
  i.mutation "4c22d0151199fe3e",
             subject: "Saboteur::Engine::RunFingerprint#cache_overlap_issues",
             reason: "equivalent: the app dir is always listed with the other project dirs, so the " \
                     "root entry in the protected list is redundant - hand-applied mutant leaves " \
                     "the engine, integration and focus e2e specs green"
  i.mutation "cd52180285b172aa",
             subject: "Saboteur::Engine::RunFingerprint#cache_overlap_issues",
             reason: "equivalent: the app dir is always listed with the other project dirs, so " \
                     "repeating the dir list instead of the root only adds a duplicate entry - " \
                     "hand-applied mutant leaves the engine, integration and focus e2e specs green"
  i.mutation "468c6fb66066699c",
             subject: "Saboteur::Engine::RunFingerprint#output_overlap_issues",
             reason: "equivalent: the manifest names are expanded against the root by " \
                     "canonical_path before use, so a relative name resolves to the same path - " \
                     "hand-applied mutant leaves the engine, integration and focus e2e specs green"
  i.mutation "eec46e4c45a11ac3",
             subject: "Saboteur::Engine::RunFingerprint#output_overlap_issues",
             reason: "equivalent: each hands back the relative manifest names, and canonical_path " \
                     "expands them against the root as the joined names would be, so the path set " \
                     "is the same - hand-applied mutant leaves the engine, integration and focus " \
                     "e2e specs green"
  i.mutation "b8d9aaf33594346f",
             subject: "Saboteur::Engine::RunFingerprint#project_files",
             reason: "equivalent: the inventory is sorted later, so the order Dir.children returns " \
                     "does not reach the digest - hand-applied mutant leaves the engine, " \
                     "integration and focus e2e specs green"
  i.mutation "ed4ce33ba5a3e84a",
             subject: "Saboteur::Engine::RunFingerprint.restore_snapshot",
             reason: "equivalent: the fields hash already carries the issues key through the " \
                     "splat, so passing issues again sets the same value - hand-applied mutant " \
                     "leaves the engine, integration and focus e2e specs green"
  i.mutation "cd1e1fdeae2cf4de",
             subject: "Saboteur::Engine::RunFingerprint.validate_snapshot_fields",
             reason: "equivalent: the each block runs for its raise and the value of the loop is " \
                     "not used, so map builds an unused array - hand-applied mutant leaves the " \
                     "engine, integration and focus e2e specs green"
  i.mutation "f11999e0da4757f2",
             subject: "Saboteur::Engine::RunFingerprint#symlinked?",
             reason: "equivalent: keeping the leading slash adds one empty path part, and joining " \
                     "an empty part gives the same path, so the same links are tested - " \
                     "hand-applied mutant leaves the engine, integration and focus e2e specs green"


  # execution/process_table.rb. Hand-applied together: spec/saboteur/execution stays green
  # (500 examples, 1 pending).
  i.mutation "be375b2b723b6afc",
             subject: "Saboteur::Execution::ProcessTable::Linux#entry_for",
             reason: "equivalent: the character after the closing paren of a stat line is always a " \
                     "space, so starting the field split one character earlier only adds a leading " \
                     "space, which split drops - hand-applied mutant leaves the execution specs " \
                     "green"
  i.mutation "27fc64f6fcd489bd",
             subject: "Saboteur::Execution::ProcessTable::Linux#snapshot",
             reason: "equivalent: Dir.children on /proc never lists an empty name, so letting the " \
                     "pid pattern match zero digits admits no extra entry - hand-applied mutant " \
                     "leaves the execution specs green"

  # gates.rb define_options and initialize. Hand-applied together: gates, cli and help specs
  # stay green (310 examples).
  i.mutation "172fa2587c30352e",
             subject: "Saboteur::Gates.define_options",
             reason: "equivalent: the each runs for the parser.on side effects and its only caller " \
                     "does not use the return value, so map builds an unused array - hand-applied " \
                     "mutant leaves gates, cli and help specs green"
  i.mutation "1a85e197156f5af9",
             subject: "Saboteur::Gates.define_options",
             reason: "equivalent: OptionParser#on tells a switch from its description by shape (a " \
                     "leading dash), not by position, so swapping the two strings builds the same " \
                     "switch and a byte-identical help line - hand-applied mutant leaves gates, " \
                     "cli and help specs green"
  i.mutation "88e5b32592d1582e",
             subject: "Saboteur::Gates#initialize",
             reason: "equivalent: Hash#to_h with a one-parameter block yields the key first, so " \
                     "mapping SETTINGS directly builds the same limits as mapping SETTINGS.keys - " \
                     "hand-applied mutant leaves gates, cli and help specs green"

  # execution/process_table.rb page_kb and reevaluator.rb resolve_path. Hand-applied together:
  # spec/saboteur/execution stays green (507 examples, 1 pending).
  i.mutation "508aa3f45dc18150",
             subject: "Saboteur::Execution::ProcessTable::Linux#page_kb",
             reason: "equivalent in a full saboteur run: crash_report.rb and external_runner.rb " \
                     "require tmpdir, which loads Etc; without the require a missing Etc would be " \
                     "rescued to the 4 KB fallback, so only a process loading process_table alone " \
                     "on a larger page would differ - hand-applied mutant leaves the execution " \
                     "specs green"
  i.mutation "4339a0680625f987",
             subject: "Saboteur::Execution::ProcessTable::Linux#page_kb",
             reason: "equivalent for power-of-two page sizes up to 512 KB: integer division by " \
                     "1023 gives the same kilobyte count as division by 1024 for 1, 2, 4, 8, 16, " \
                     "32 and 64 KB pages and every size to 512 KB - hand-applied mutant leaves the " \
                     "execution specs green"
  i.mutation "19d4e9c1e0125d9c",
             subject: "Saboteur::Execution::Reevaluator#resolve_path",
             reason: "equivalent given Object.const_get behavior: const_get accepts a leading :: " \
                     "and resolves from Object, so keeping the prefix returns the same constant as " \
                     "stripping it - hand-applied mutant leaves the execution specs green"
  # execution/reevaluator.rb. Hand-applied (one variant per line): the reevaluator specs and the
  # execution specs stay green (556 examples).
  i.mutation "1cc23f3a89fbfff9",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: for a singleton def or a Class owner the later checks fail " \
                     "anyway, because the owner's own instance and singleton copies do not share " \
                     "one source location, so the guard and its early return value (nil or false " \
                     "are both falsy at the one caller) change no result - hand-applied mutant " \
                     "leaves the reevaluator pin specs and the execution specs green"
  i.mutation "aa848f36f91e6887",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: for a singleton def or a Class owner the later checks fail " \
                     "anyway, because the owner's own instance and singleton copies do not share " \
                     "one source location, so the guard and its early return value (nil or false " \
                     "are both falsy at the one caller) change no result - hand-applied mutant " \
                     "leaves the reevaluator pin specs and the execution specs green"
  i.mutation "fe861541e692b38e",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: for a singleton def or a Class owner the later checks fail " \
                     "anyway, because the owner's own instance and singleton copies do not share " \
                     "one source location, so the guard and its early return value (nil or false " \
                     "are both falsy at the one caller) change no result - hand-applied mutant " \
                     "leaves the reevaluator pin specs and the execution specs green"
  i.mutation "64df90c70044ef90",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: for a singleton def or a Class owner the later checks fail " \
                     "anyway, because the owner's own instance and singleton copies do not share " \
                     "one source location, so the guard and its early return value (nil or false " \
                     "are both falsy at the one caller) change no result - hand-applied mutant " \
                     "leaves the reevaluator pin specs and the execution specs green"
  i.mutation "209f623772d003c7",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of private_method_defined? and a nil instead of " \
                     "false return change no result, since a method inherited from an ancestor " \
                     "cannot share its source location with the owner's singleton copy and the " \
                     "caller only tests truthiness - hand-applied mutant leaves the reevaluator " \
                     "pin specs and the execution specs green"
  i.mutation "2392970126da3a9a",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of private_method_defined? and a nil instead of " \
                     "false return change no result, since a method inherited from an ancestor " \
                     "cannot share its source location with the owner's singleton copy and the " \
                     "caller only tests truthiness - hand-applied mutant leaves the reevaluator " \
                     "pin specs and the execution specs green"
  i.mutation "f6b914ccfc734e5b",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of private_method_defined? and a nil instead of " \
                     "false return change no result, since a method inherited from an ancestor " \
                     "cannot share its source location with the owner's singleton copy and the " \
                     "caller only tests truthiness - hand-applied mutant leaves the reevaluator " \
                     "pin specs and the execution specs green"
  i.mutation "4545040b39a91e40",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of method_defined? on the singleton class and a " \
                     "nil instead of false return change no result, since an inherited singleton " \
                     "method cannot share its source location with the owner's instance method and " \
                     "the caller only tests truthiness - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "bbd7cd189eb9e010",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of method_defined? on the singleton class and a " \
                     "nil instead of false return change no result, since an inherited singleton " \
                     "method cannot share its source location with the owner's instance method and " \
                     "the caller only tests truthiness - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "ecdb50612ca010bd",
             subject: "Saboteur::Execution::Reevaluator#module_function?",
             reason: "equivalent: the inherit flag of method_defined? on the singleton class and a " \
                     "nil instead of false return change no result, since an inherited singleton " \
                     "method cannot share its source location with the owner's instance method and " \
                     "the caller only tests truthiness - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "ff5de612348efb90",
             subject: "Saboteur::Execution::Reevaluator#eval_whole_file",
             reason: "equivalent: Kernel#eval and Binding#eval default the line number to 1, so " \
                     "leaving out the explicit 1 evaluates the file from the same first line - " \
                     "hand-applied mutant leaves the reevaluator pin specs and the execution specs " \
                     "green"
  i.mutation "214d3eabce9ba105",
             subject: "Saboteur::Execution::Reevaluator#aliases_of",
             reason: "equivalent: aliases_of keeps only methods whose original name and source " \
                     "location equal the current definition, and an inherited method cannot share " \
                     "the target's source location, so the inherit arguments change which names " \
                     "are scanned but not which aliases are found - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "7e6ddb2d8f27efa8",
             subject: "Saboteur::Execution::Reevaluator#aliases_of",
             reason: "equivalent: aliases_of keeps only methods whose original name and source " \
                     "location equal the current definition, and an inherited method cannot share " \
                     "the target's source location, so the inherit arguments change which names " \
                     "are scanned but not which aliases are found - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "8229ed61b29cb71b",
             subject: "Saboteur::Execution::Reevaluator#aliases_of",
             reason: "equivalent: aliases_of keeps only methods whose original name and source " \
                     "location equal the current definition, and an inherited method cannot share " \
                     "the target's source location, so the inherit arguments change which names " \
                     "are scanned but not which aliases are found - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "b52d9f0dd4ebe6b6",
             subject: "Saboteur::Execution::Reevaluator#aliases_of",
             reason: "equivalent: aliases_of keeps only methods whose original name and source " \
                     "location equal the current definition, and an inherited method cannot share " \
                     "the target's source location, so the inherit arguments change which names " \
                     "are scanned but not which aliases are found - hand-applied mutant leaves the " \
                     "reevaluator pin specs and the execution specs green"
  i.mutation "4d6c9191d8c0556e",
             subject: "Saboteur::Execution::Reevaluator#repoint",
             reason: "equivalent: the each runs for its alias_method and visibility side effects " \
                     "and no caller uses its value, so map builds an unused array - hand-applied " \
                     "mutant leaves the reevaluator pin specs and the execution specs green"
  i.mutation "b2a997da0b33ca97",
             subject: "Saboteur::Execution::Reevaluator#restore",
             reason: "equivalent: sending a visibility of public to the target is a no-op, so " \
                     "changing or dropping the != :public test only adds a public re-send - " \
                     "hand-applied mutant leaves the reevaluator pin specs and the execution specs " \
                     "green"
  i.mutation "b8ecc89615c8af41",
             subject: "Saboteur::Execution::Reevaluator#restore",
             reason: "equivalent: sending a visibility of public to the target is a no-op, so " \
                     "changing or dropping the != :public test only adds a public re-send - " \
                     "hand-applied mutant leaves the reevaluator pin specs and the execution specs " \
                     "green"
  i.mutation "ba5814fcfe397a75",
             subject: "Saboteur::Execution::Reevaluator#restore",
             reason: "equivalent: sending a visibility of public to the target is a no-op, so " \
                     "always taking the branch only adds a public re-send - hand-applied mutant " \
                     "leaves the reevaluator pin specs and the execution specs green"

  # mutation_source/builtin.rb. Replayed by id (survived, or no coverage for d25ab320)
  # and hand-applied with green mutation_source specs.
  i.mutation "592ebb9c7020c4a6",
      subject: "Saboteur::MutationSource::Builtin#visit",
      reason: "The each over child nodes only recurses for its side effects, and the return " \
              "value of visit is never used, so map behaves the same."
  i.mutation "77e91c08bd178586",
      subject: "Saboteur::MutationSource::Builtin#visit_statements",
      reason: "The each over statements only adds mutations as a side effect, and the return " \
              "value of visit_statements is never used, so map behaves the same."
  i.mutation "e75a28fb97c53522",
      subject: "Saboteur::MutationSource::Builtin#mutate_condition",
      reason: "The each over the literals only calls add for its side effect, and the return " \
              "value of mutate_condition is never used, so map behaves the same."
  i.mutation "a394a657450f3564",
      subject: "Saboteur::MutationSource::Builtin#mutate_number",
      reason: "The each over the candidates only calls add for its side effect, and the " \
              "return value of mutate_number is never used, so map behaves the same."
  i.mutation "946ec5983bee6b05",
      subject: "Saboteur::MutationSource::Builtin#initialize",
      reason: "The class inherits from Base, which defines no initialize, so super() only " \
              "reaches Object#initialize and does nothing."
  i.mutation "2fc4e04fad073911",
      subject: "Saboteur::MutationSource::Builtin#initialize",
      reason: "Regexp.new on a Regexp returns an equal regexp with the same source and " \
              "options, so passing the pattern through changes no match."
  i.mutation "0058d11ad0d6ba62",
      subject: "Saboteur::MutationSource::Builtin#arid_statement?",
      reason: "The only callers use the result for truthiness (next if, all?), so nil and " \
              "false behave the same."
  i.mutation "6f965b513aedd32f",
      subject: "Saboteur::MutationSource::Builtin#arid_statement?",
      reason: "The only callers use the result for truthiness (next if, all?), so nil and " \
              "false behave the same."
  i.mutation "bd987b6f95f80465",
      subject: "Saboteur::MutationSource::Builtin#add",
      reason: "Mutation defaults source to builtin, which is what Builtin#name returns, so " \
              "leaving source out gives the same value."
  i.mutation "3e8e7eac03be67f7",
      subject: "Saboteur::MutationSource::Builtin#removable?",
      reason: "A bare nil statement would be replaced by nil, and add returns early when the " \
              "replacement equals the original slice, so keeping nil removable adds no " \
              "mutation."
  i.mutation "d25ab320f80cbf90",
      subject: "Saboteur::MutationSource::Builtin#removable?",
      reason: "A bare nil statement would be replaced by nil, and add returns early when the " \
              "replacement equals the original slice, so returning true for nil adds no " \
              "mutation."
  i.mutation "21c2262af6e842f1",
      subject: "Saboteur::MutationSource::Builtin#numeric_operands?",
      reason: "Only infix operator calls reach this check, and they have exactly one " \
              "argument, so the first and last argument are the same node."

  # reporter/agent.rb. Replayed by id with the agent reporter, cli and crash
  # report specs (survived) and hand-applied with 882 green examples.
  i.mutation "49ed6811d9d64e9c",
      subject: "Saboteur::Reporter::Agent.minimal",
      reason: "The snippet limit only clips the shown findings, and minimal shows none (shown is " \
              "0), so the first and last limit give the same payload."
  i.mutation "7fbe28b6d558f860",
      subject: "Saboteur::Selection::CoverageMap#ran_at_load?",
      reason: "Returning nil instead of false when the file has no load-time lines changes nothing: " \
              "every caller only tests the result for truthiness."

  i.mutation "6c3afec3a0cc2e9f",
      subject: "Saboteur::MutantResult#initialize",
      reason: "equivalent: dropping the nil assignment leaves @ignored unset, and " \
              "its attr_accessor reads nil either way"

  i.mutation "9f8181342421ae56",
      subject: "Saboteur::MutantResult#relative",
      reason: "equivalent: the start_with? guard is redundant, delete_prefix returns " \
              "the same string when the prefix is absent"

  i.mutation "377c0c58c6ebdbf8",
      subject: "Saboteur::MutantResult#relative",
      reason: "equivalent: the start_with? guard is redundant, delete_prefix returns " \
              "the same string when the prefix is absent"

  i.mutation "c723040b7f052d92",
      subject: "Saboteur::MutantResult#relative",
      reason: "equivalent: the start_with? guard is redundant, delete_prefix returns " \
              "the same string when the prefix is absent"

  i.mutation "769eb626f6f7a771",
      subject: "Saboteur::Replay#select",
      reason: "equivalent: each and map differ only in the returned array, and the " \
              "block's result is discarded"


  i.mutation "f7058d3116116d65",
      subject: "Saboteur::SubjectFinder#heredoc_eval?",
      reason: "equivalent: its only caller, walk_call, tests it as an if condition, " \
              "so nil and false take the same branch"

  i.mutation "da2797abc9e66630",
      subject: "Saboteur::SubjectFinder#heredoc_eval?",
      reason: "equivalent: its only caller, walk_call, tests it as an if condition, " \
              "so nil and false take the same branch"

  i.mutation "73fbc92a1f878817",
      subject: "Saboteur::SubjectFinder#define_method_subject?",
      reason: "equivalent: its only caller, call_defined_method?, returns it from a " \
              "case branch that walk_call tests as a condition"

  i.mutation "52aff07c1854d240",
      subject: "Saboteur::SubjectFinder#call_defined_method?",
      reason: "equivalent: its only caller, walk_call, tests it with unless, so nil " \
              "and false take the same branch"

  i.mutation "e5dd5501fca8ba1d",
      subject: "Saboteur::SubjectFinder#call_defined_method?",
      reason: "equivalent: its only caller, walk_call, tests it with unless, so nil " \
              "and false take the same branch"

  i.mutation "24041e831b061953",
      subject: "Saboteur::SubjectFinder#class_factory?",
      reason: "equivalent: its only caller, walk_constant_assignment, tests it with " \
              "unless, so nil and false take the same branch"

  i.mutation "8c405e2c95dc2bad",
      subject: "Saboteur::SubjectFinder#class_factory?",
      reason: "equivalent: its only caller, walk_constant_assignment, tests it with " \
              "unless, so nil and false take the same branch"


  i.mutation "996870a6910e3aa8",
      subject: "Saboteur::ConstantSubjectFinder::Unsupported#overlaps_lines?",
      reason: "equivalent: node.location.start_line and node.start_line are the same " \
              "value, Prism::Node delegates to its location"

  i.mutation "43fcfd0dcdf96fba",
      subject: "Saboteur::ConstantSubjectFinder::Unsupported#overlaps_lines?",
      reason: "equivalent: node.location.end_line and node.end_line are the same " \
              "value, Prism::Node delegates to its location"

  i.mutation "827e6ee80caf11ec",
      subject: "Saboteur::ConstantSubjectFinder#factory_scope?",
      reason: "equivalent: its only caller, walk_constant_assignment, tests it in an " \
              "if, so nil and false take the same branch"

  i.mutation "6c6b84a27b7bb8e6",
      subject: "Saboteur::ConstantSubjectFinder#factory_scope?",
      reason: "equivalent: its only caller, walk_constant_assignment, tests it in an " \
              "if, so nil and false take the same branch"

  i.mutation "6f7e6334b5c3918a",
      subject: "Saboteur::InlineSuppression#parse",
      reason: "equivalent: Prism::Comment#slice and comment.location.slice return " \
              "the same text"

  i.mutation "1d150c3ba6b0f757",
      subject: "Saboteur::InlineSuppression#parse",
      reason: "equivalent: an inline comment starts with the hash so the unanchored match hits the same " \
              "place, and an embdoc comment starts with =begin, which the start_with? guard rejects either way"


  i.mutation "f2e1cce1752bfa67",
      subject: "Saboteur::Preview#print_warnings",
      reason: "equivalent: each and map differ only in the returned array, and the " \
              "block's result is discarded"

  i.mutation "e8bb5faf01cf1ebe",
      subject: "Saboteur::Preview#inline_suppressions",
      reason: "equivalent: each and map differ only in the returned array, and the " \
              "block's result is discarded"

  i.mutation "6d79acab4b409bd8",
      subject: "Saboteur::Preview#incomplete_note",
      reason: "equivalent: the result is only interpolated into the total line, " \
              "where nil and an empty string print the same"

  i.mutation "61fabb208a389865",
      subject: "Saboteur::Install#missing_entry",
      reason: "equivalent: the result is only interpolated into the written text, " \
              "where nil and an empty string add the same"

  i.mutation "ada593a8ce1774ee",
      subject: "Saboteur::Subject#innermost_statement",
      reason: "equivalent: node is nil only for a nil start, where found is nil too, " \
              "so both returns give nil"


  # engine/candidates.rb. Replayed by id with the candidates, selection, since
  # scope, preview and replay specs (survived) and hand-applied green.
  i.mutation "75dae99069503875",
      subject: "Saboteur::Engine::Candidates#for",
      reason: "The sort key only needs coarse mutations before the rest, and the key 0 or -1 both " \
              "sort ahead of 1, so the order is the same."


  # integration/rspec.rb LoadErrorReport. Replayed by id with the rspec integration specs
  # (survived) and hand-applied with the load error and listener specs green.
  i.mutation "27b27bfb3709cdca",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.saboteur_frame?",
      reason: "The line already starts with a hash and a space, so one-or-more and " \
              "zero-or-more whitespace strip the same prefix before the path check."
  i.mutation "4225860140870760",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.saboteur_frame?",
      reason: "Only the start of the path is read, so one-or-more and zero-or-more " \
              "digits before the in marker leave the same prefix."
  i.mutation "609658fd29032dac",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.saboteur_frame?",
      reason: "Only the start of the path is read, so a star and a plus after the " \
              "in marker drop the same tail."
  i.mutation "a754bab757b852e2",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.saboteur_frame?",
      reason: "The pattern ends in a greedy any-run that already reaches the end " \
              "of the line, so the end anchor changes nothing."
  i.mutation "bb8c680d186f9ec2",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.saboteur_frame?",
      reason: "The line already starts with a hash and a space, so the prefix pattern " \
              "can only match at the start, with or without the start anchor."
  i.mutation "8854885f87106e1a",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.filter",
      reason: "kept always holds at least the first header line, so kept.last is " \
              "never nil and the safe navigation is never needed."
  i.mutation "1367729198528185",
      subject: "Saboteur::Integration::RSpec::LoadErrorReport.filter",
      reason: "omitted is at least 1 here, so omitted > 1 and omitted != 1 pick " \
              "the same plural suffix."

  # integration/rspec.rb setup L27/L33: the literal fallbacks in
  # config.fetch('seed', 1) and config.fetch("verbose", false) are unreachable -
  # Config::DEFAULTS always supplies "seed" => 1 and "verbose" => false, so the
  # fetch never falls back. Replayed by id (survived on the narrow and the wide
  # base spec set) and each hand-applied mutant leaves the 109 integration
  # examples green.
  i.mutation "f934953633f024c8",
      subject: "Saboteur::Integration::RSpec#setup",
      reason: "Equivalent: Config::DEFAULTS supplies 'seed' => 1, so the changed fallback in " \
              "config.fetch('seed', 1) is never used; hand-applied mutant leaves 109 " \
              "integration examples green."
  i.mutation "77329da0e4287e81",
      subject: "Saboteur::Integration::RSpec#setup",
      reason: "Equivalent: same unreachable seed fallback, mutated to 0; Config::DEFAULTS " \
              "'seed' => 1 always wins and 109 integration examples stay green."
  i.mutation "b81d038f7dcdc6ac",
      subject: "Saboteur::Integration::RSpec#setup",
      reason: "Equivalent: dropping the seed fallback still reads Config::DEFAULTS 'seed' => 1; " \
              "hand-applied mutant leaves 109 integration examples green."
  i.mutation "f61626e40af76c6c",
      subject: "Saboteur::Integration::RSpec#setup",
      reason: "Equivalent: Config::DEFAULTS supplies 'verbose' => false, so flipping the " \
              "fallback to true is never used; hand-applied mutant leaves 109 integration " \
              "examples green."
  i.mutation "b376de8b8be740c7",
      subject: "Saboteur::Integration::RSpec#setup",
      reason: "Equivalent: dropping the verbose fallback still reads Config::DEFAULTS " \
              "'verbose' => false; hand-applied mutant leaves 109 integration examples green."

  # integration/rspec.rb: the default-argument fallbacks of config.fetch for
  # "rspec_args" and "tests" are unreachable (Config::DEFAULTS supplies both as
  # []), and the configured default_path never reaches RSpec file selection:
  # files_or_directories_to_run= only prepends default_path when $0 is rspec,
  # and get_files_to_run falls back to Dir.getwd. Replayed by id (survived on
  # the narrow and the wide base spec set); each hand-applied mutant leaves
  # the 111 integration examples green.
  i.mutation "b4f84646b4749adb",
      subject: "Saboteur::Integration::RSpec#rspec_args",
      reason: "Equivalent: Config::DEFAULTS supplies 'rspec_args' => [], so the dropped " \
              "fallback is never used; hand-applied mutant leaves 111 integration examples green."
  i.mutation "cf47b4f1229d0420",
      subject: "Saboteur::Integration::RSpec#configuration_options",
      reason: "Equivalent: Config::DEFAULTS supplies 'tests' => [], so the dropped fallback " \
              "is never used; hand-applied mutant leaves 111 integration examples green."
  i.mutation "27cf3a48e1dd51ec",
      subject: "Saboteur::Integration::RSpec#configured_spec_files",
      reason: "Equivalent: RSpec prepends default_path only when $0 is rspec and " \
              "get_files_to_run falls back to Dir.getwd, so the configured default_path " \
              "never changes files_to_run here; hand-applied mutant leaves 111 integration " \
              "examples green."
  # worker_pool.rb:215 - the loop is the last expression of abandon_all, so each versus map
  # only changes the return value, and its only caller (collect) ignores it and returns.
  i.mutation "19beb925eb189d79",
             subject: "Saboteur::Execution::WorkerPool#abandon_all",
             reason: "equivalent: the second loop is the method's last expression, so each versus " \
                     "map changes only the return value, which the only caller (collect) ignores"
  i.mutation "e44cdce1a20e3a31",
             subject: "Saboteur::Execution::WorkerPool#collect",
             reason: "equivalent: the return value of the dead-worker replacement loop is unused by " \
                     "collect's only caller, distribute, so each and map replace the same workers"
  # worker_pool.rb:81 - order = items.each_index.sort_by { |index| [-(weights ? weights[index] : 0), index] }
  # The default weight is used only when there are no weights, so every item gets the same
  # key part and every key shifts equally: the order does not change.
  i.mutation "2ee9981587e79e3d",
             subject: "Saboteur::Execution::WorkerPool#map",
             reason: "equivalent: the default weight is used only when no weights are given, so " \
                     "-0 becoming 1 or -1 shifts every item's key equally and the order is unchanged"
  i.mutation "9feec60128f111d3",
             subject: "Saboteur::Execution::WorkerPool#map",
             reason: "equivalent: the default weight is used only when no weights are given, so " \
                     "-0 becoming 1 or -1 shifts every item's key equally and the order is unchanged"
  # Results are written by item index, so dropping the index tiebreak from the sort key can
  # only change the order in which tied items are dispatched, never the returned array.
  # sort_by is not guaranteed stable, so no spec can hold that order on every platform.
  i.mutation "472eb17a70036d49",
             subject: "Saboteur::Execution::WorkerPool#map",
             reason: "equivalent: results are stored by item index, so without the index tiebreak " \
                     "only the dispatch order of equal-weight items can change, and sort_by does " \
                     "not guarantee that order on every platform, so no spec can hold it"
  # survivor_confirmation.rb:120 - the runtime literal on the :unverified Outcome built when the
  # confirmation budget is spent. VerdictCheck never reads outcome.runtime for an unverified
  # outcome, so the value is write-only and 0.0 -> 1.0 / -1.0 change nothing observable.
  i.mutation "78b7712d6a95a847",
             subject: "Saboteur::Engine::SurvivorConfirmation#unchanged_runner",
             reason: "equivalent: write-only value - the :unverified Outcome's runtime is never " \
                     "read, so changing the literal leaves behavior unchanged"
  i.mutation "bf4d60fb4a8fe2d9",
             subject: "Saboteur::Engine::SurvivorConfirmation#unchanged_runner",
             reason: "equivalent: write-only value - the :unverified Outcome's runtime is never " \
                     "read, so changing the literal leaves behavior unchanged"
  # survivor_confirmation.rb:95 - VerdictCheck is called with the guaranteed one-element array
  # [kill], so .first and .last pick the same result.
  i.mutation "2d056fcf11e5c9c4",
             subject: "Saboteur::Engine::SurvivorConfirmation#checked_kill",
             reason: "equivalent: .first and .last pick the same element of the one-element " \
                     "[kill] array the check is called with, so the returned result is identical"
  # Score-honesty PR (head 048103f671d065c28765ab31ec5751cce8f64026) dogfood
  # survivors; each per-id replay diff was inspected and proven unobservable.
  # Until that PR lands these digests match nothing and read as stale.
  i.mutation "66e3a0cfce46abb7",
             subject: "Saboteur::Reporter::ScoreTable#untested_subjects",
             reason: "equivalent: dropping subject.file from the sort key is unobservable - the " \
                     "sorted list is only consumed via group_by(&:file), and within one file " \
                     "[start_line] sorts identically to [file, start_line]"
  i.mutation "389aea458ec95382",
             subject: "Saboteur::Reporter::ScoreTable#untested_note",
             reason: "equivalent: map(&:id) -> each(&:id) returns the subjects themselves, and the " \
                     "only uses (first, size, join) go through Subject#to_s, which returns id " \
                     "(subject.rb:188) - the printed note is byte-identical"
  i.mutation "ad3d5b107c446ee8",
             subject: "Saboteur::Reporter::Terminal#error_part",
             reason: "equivalent: rejected > 1 -> rejected != 1 sits behind rejected.positive?, " \
                     "and for integers >= 1 the two predicates agree"
end
