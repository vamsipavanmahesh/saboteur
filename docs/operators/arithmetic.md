# arithmetic

Swaps an arithmetic operator: `+` with `-` and `*` with `/`
(`a + b` becomes `a - b`). Only the infix spelling is treated as binary.
Non-numeric literals (strings, arrays, hashes, symbols and friends) are left
to the operators that handle them.

Runs by default. Use `--operators arithmetic` to select it alone, or
`--exclude-operators arithmetic` to leave it out. A swap survives when the
operands mask it: adding or subtracting zero, multiplying or dividing by
one, or a test that never checks the result's value. Strengthen the
assertion rather than assuming equivalence.
