# body_nil

Replaces the whole method body with `nil`. One of the coarse whole-body
mutants, generated first for every method whose body is not empty or only
logging (replacing those would change nothing a test can see). Predicate
methods (ending in `?`) get `body_true` and `body_false` instead, since a
predicate's `nil` is just `false`. Fine-grained mutants run regardless of
whether this one survives.

Runs by default. Use `--operators body_nil` to select it alone, or
`--exclude-operators body_nil` to leave it out. Almost any test that runs
the method kills it, so a survivor is a strong hint that no test pins the
method's behavior at all - and the score excluding whole-body mutants
(`saboteur.scores.withoutWholeBodyMutants` in the JSON report) says more
about how well values are checked.
