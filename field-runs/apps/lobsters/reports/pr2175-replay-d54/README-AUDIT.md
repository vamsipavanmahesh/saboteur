# PR 2175 row audit (merger, 2026-10-24)

Exit 3 (uncovered), 1 subject Comment.for_presentation (comment.rb:66) skipped, wall 12.85s (measurement.json). Snapshot copy hashes match the merger's own verified copies (coverage c379bc36..., inputs ce3cfa37..., pointer c9fc0a72...). First attempt (logs/pr2175-replay-d54-20261024.log, wall 25.28s) ran ungated after a failed snapshot copy and is INVALID; the gated rerun (d54b) is the row of record.

Classification (D57): NOT a test gap. The reused map's line table records 63 tests executing the scope body (comment.rb:67) at the snapshot tree 9a773eac; the subject-level miss is a keying limit (scope lambdas have no methods-table entry). Unmeasurable via this path; non-scored; excluded from noise numerators.
