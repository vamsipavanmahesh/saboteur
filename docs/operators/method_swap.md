# method_swap

Swaps a method whose name has a semantic opposite: `min` with `max`, `any?` with `all?`, `map` with `each`. Only the message bytes change; receiver, arguments and block stay intact. A receiver is required, so a bare `max(a, b)` Kernel call is left alone. Arid expressions and nested definitions are skipped; the normal parser, dedupe and cap checks apply.

Runs by default. Use `--operators method_swap` to select it alone, or `--exclude-operators method_swap` to leave it out. A swap can be equivalent when the test's inputs make both names return the same value (a one-element collection for `min`/`max`, an empty one for `any?`/`all?`); review the result and effects rather than assuming a survivor is a bug.

Closes the operator gap reported in #237: `[[x, lo].max, hi].min` previously got only whole-body mutants.
