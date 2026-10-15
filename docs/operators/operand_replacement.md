# operand_replacement

Replaces a binary operation with each of its operands in turn: `a + b` yields `a` and `b`. Arithmetic (`+ - * / % **`) and comparison (`< <= > >= == !=`) calls only; boolean connectors stay with `boolean_logic`, which already replaces a connector with each side. Only the plain binary shape (receiver, one argument, no block) is touched. An operand binds at least as tightly as the operation it replaces, so no parentheses are added; the re-parse check backs this.

Runs by default. Use `--operators operand_replacement` to select it alone, or `--exclude-operators operand_replacement` to leave it out. Equivalent-mutant notes: symmetric expressions (`a + a`) yield twice the same replacement and collapse under the normal dedupe; an operand the surrounding code never reads survives equivalent by design. Review the result and effects rather than assuming a survivor is a bug.

Closes the operator gap reported in #238: `a + b` previously got only `a - b`, so a test that cannot tell the sum from either operand survived unseen.
