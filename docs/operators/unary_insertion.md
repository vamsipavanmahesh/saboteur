# unary_insertion

Inserts a unary operator before one operand at a time: `!` before an operand of `&&` or `||`, and `-` before an operand of an arithmetic call (`+ - * / % **`). `a && b` yields `!a && b` and `a && !b`; `x - y` yields `-x - y` and `x - -y`. Only leaf operands (variables, instance variables, calls) are touched: literals stay with the literal operators, a bare predicate with condition_negation, and an operand that already carries `!`, `-` or `~` is left alone. A binary call with a String on either side is concatenation, not arithmetic, and is skipped, since unary `-` keeps a String's characters. Calls written with an explicit dot (`x.+(y)`) are not covered.

Runs by default. Use `--operators unary_insertion` to select it alone, or `--exclude-operators unary_insertion` to leave it out. The mutant survives when no test depends on the operand's sign or truthiness on its own. Add an example where the operand alone decides the result.
