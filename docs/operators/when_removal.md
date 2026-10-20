# when_removal

Deletes one `when` branch of a `case` at a time, so the values it matched fall through to the next branch or the `else`. `case x; when 1 then :a; when 2 then :b; end` yields one mutant without the `1` branch and one without the `2` branch. A `case` with a single `when` is left alone, since a `case` with no `when` does not parse. Branches that open a heredoc, nested definitions and arid statements are skipped. Pattern-matching `case/in` is not covered.

Runs by default. Use `--operators when_removal` to select it alone, or `--exclude-operators when_removal` to leave it out. The mutant survives when no test sends a value that only this branch handles, or when the branch and the code after it give the same result. Add a case that takes the branch and assert its result.
