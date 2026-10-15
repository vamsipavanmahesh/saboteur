# interpolation_removal

Removes one piece of an interpolated string at a time: each `#{expr}` and each literal segment. `"Hello, #{name}!"` yields `"Hello, !"`, `"#{name}!"` and `"Hello, #{name}"`. Plain strings stay with `literal_replacement`; backticks stay untouched and are owned by the hazard guard. Arid expressions and nested definitions are skipped; the normal parser, dedupe and cap checks apply.

Runs by default. Use `--operators interpolation_removal` to select it alone, or `--exclude-operators interpolation_removal` to leave it out. A removal survives when the test never observes the removed piece: a prefix-only assertion does not see a trailing interpolation. That is a gap in the test's assertions, not proof the mutant is equivalent, so strengthen the assertion rather than ignoring the survivor. Inside a hazardous call such as `system("rm -rf #{dir}")` the hazard guard suppresses these mutants, since the altered command still runs.

Closes the operator gap reported in #239: interpolated strings previously got no mutants at all.
