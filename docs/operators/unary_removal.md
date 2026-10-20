# unary_removal

Drops a unary minus or bitwise complement from its operand: `-x` becomes `x`, `-(a + b)` becomes `(a + b)`, and `~mask` becomes `mask`. Only the prefix spelling is mutated; `x.-@` reads as a call. Unary plus is left alone because it returns numbers unchanged. `!` stays with `negation_removal`, and a negative literal such as `-1` is a number owned by `literal_number`. Nested definitions and arid statements are skipped.

Runs by default. Use `--operators unary_removal` to select it alone, or `--exclude-operators unary_removal` to leave it out. The mutant survives when every value the tests use makes the sign or the complement invisible, for example zero. Add a case with a non-zero value and assert the exact result.
