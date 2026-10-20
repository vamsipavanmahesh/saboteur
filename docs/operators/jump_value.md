# jump_value

Replaces the value carried by `return`, `next` or `break` with `nil`: `return total` becomes `return nil`, and `next x` becomes `next nil`. `return a, b` becomes `return nil`. A bare jump, a jump that already returns `nil`, and a jump whose value is a heredoc get no mutant. Setters and `initialize` are skipped, since the caller discards what they return. Arid statements and nested definitions are skipped.

Runs by default. Use `--operators jump_value` to select it alone, or `--exclude-operators jump_value` to leave it out. The mutant survives when no test checks the value an early exit hands back: the method runs, but its result is never compared. Assert the returned value on the path that takes the early exit.
