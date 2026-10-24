# PR 2205 row audit (merger, 2026-10-24)

Exit 3, 0 mutants, 2 subjects skipped "no coverage" (Story#is_hidden_by_user? :780, Story#is_saved_by_user? :788), wall 47.31s. Snapshot copy hashes verified.

Classification (D57): both skips are stale-map line drift, NOT gaps. At the snapshot tree the two methods sit at story.rb:774/:782 with body lines 775/783 each executed by 24 tests. A corrective scoped row-tree run (--test with the covering specs) is queued before any qualification.
