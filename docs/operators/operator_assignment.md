# operator_assignment

Swaps `+=` with `-=` and `*=` with `/=`. Edits only the operator bytes and preserves the target and its receiver/index evaluation. Supports local, instance, class, global, constant, attribute and index assignments. Leaves `||=`, `&&=`, plain assignment and other arithmetic operators alone. Arid expressions and nested definitions are skipped; the normal parser, dedupe and per-method cap still apply.

Runs by default. Use `--operators operator_assignment` to select it alone, or `--exclude-operators operator_assignment` to leave it out. Custom objects can implement these methods with equal results, and zero values can mask multiplication/division differences. Review survivors with those possibilities in mind.

Committed fixture `assignments` adds two candidates: one killed by an addition assertion, one survivor because the test exercises only zero. The survivor is a real untested nonzero behavior, not an equivalent mutant.

Inspired by mutineer's extra mutation operators (github.com/davidteren/mutineer, MIT, by David Teren).
