# ensure_removal

Deletes the `ensure` clause of a begin block, method body or do block, so the cleanup it runs is skipped: `begin; x; ensure; y; end` yields `begin; x; end`. A `rescue` or `else` clause beside it stays. Clauses that open a heredoc, nested definitions and arid statements are skipped.

Runs by default. Use `--operators ensure_removal` to select it alone, or `--exclude-operators ensure_removal` to leave it out. The mutant survives when no test checks what the cleanup does, such as closing a handle, restoring state or releasing a lock. Add a case that checks that effect after a normal run and after a raising one. Removing the clause's own statements is `statement_removal`, not this operator.
