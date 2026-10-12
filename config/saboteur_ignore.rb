# Survivors accepted with a reason. Each digest is printed next to its survivor.
Saboteur.ignore do |i|
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

  i.mutation "0f79546512131b47",
             subject: "Saboteur::MutationSource::Builtin#initialize",
             reason: "equivalent: Base#initialize does nothing"

  i.mutation "22d70abfce019634",
             subject: "Saboteur::MutationSource::Builtin#initialize",
             reason: "equivalent: Regexp.new(regexp) returns an equal Regexp"

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

  i.mutation "1356ffa727eb6c28",
             subject: "Saboteur::MutationSource::Builtin#binary?",
             reason: "equivalent: calls named as operators are binary in practice"

  i.mutation "557d74f40af55855",
             subject: "Saboteur::MutationSource::Builtin#mutate_number",
             reason: "equivalent: add drops a replacement whose text equals the original"

  i.mutation "9ac4abd82021b00e",
             subject: "Saboteur::Selection::Recorder#test_finished",
             reason: "equivalent: test_started always runs first, so @started_at is set"

  i.mutation "0458d7ba8548398b",
             subject: "Saboteur::Selection::CoverageMap#to_json",
             reason: "equivalent: durations only order tests; a digit of rounding changes no order in practice"

  i.mutation "888ad02d4ded3205",
             subject: "Saboteur::Selection::CoverageMap#to_json",
             reason: "equivalent: durations only order tests; a digit of rounding changes no order in practice"

  i.mutation "0bc08834912bc67d",
             subject: "Saboteur::Selection::CoverageMap#test_order",
             reason: "equivalent: memoization only; tests never change after construction"

  i.mutation "65fbe2a08ec0b22f",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: git quotes a whole path, so a path that starts with a quote also ends with one"

  i.mutation "bd07c16b6d849639",
             subject: "Saboteur::Selection::GitDiff#unquote",
             reason: "equivalent: git quotes a whole path, so a path that starts with a quote also ends with one"

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

  i.mutation "3f4731752cdbf4a2",
             subject: "Saboteur::CustomMap#duplicate_keys",
             reason: "equivalent: counts are always at least 1, so != 1 selects the same keys as > 1"

  i.mutation "2e6104adf15e225f",
             subject: "Saboteur::CustomMap#glob_entry",
             reason: "equivalent: best is never empty, so != 1 and > 1 agree"

  i.mutation "af7d1164240f82ca",
             subject: "Saboteur::CustomMap#resolve",
             reason: "equivalent: a spec with a backreference only validates under a Regexp key, where match is always present"

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
end
