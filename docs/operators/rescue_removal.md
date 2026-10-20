# rescue_removal

Deletes one exception handler at a time, so the error it caught propagates: each `rescue` clause of a begin block or method body, and the `rescue value` tail of a modifier. `begin; x; rescue A; y; rescue B; z; end` yields one mutant without the `A` clause and one without the `B` clause. `value = risky rescue nil` yields `value = risky`. The only handler of a block that also has an `else` is kept, since `else` without `rescue` does not parse. Handlers that open a heredoc, nested definitions and arid statements are skipped.

Runs by default. Use `--operators rescue_removal` to select it alone, or `--exclude-operators rescue_removal` to leave it out. The mutant survives when no test makes the guarded code raise the rescued error, so the handler never runs. Add a case where the code raises and assert what the handler returns or does. Removing the handler's own statements is `statement_removal`, not this operator.
