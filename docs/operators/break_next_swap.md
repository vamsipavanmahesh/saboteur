# break_next_swap

Swaps the loop-control keyword: `break` becomes `next` and `next` becomes `break`, keeping any jumped value. `break x` yields `next x`; `next` yields `break`. A break that ended the loop becomes an iteration skip and the other way round. The jumped value itself is left to jump_value.

Runs by default. Use `--operators break_next_swap` to select it alone, or `--exclude-operators break_next_swap` to leave it out. The mutant survives when no test observes the loop's result or its side effects, or when the loop only ever runs one iteration. Add an example that runs the loop past the jumped iteration and asserts what it leaves behind.
