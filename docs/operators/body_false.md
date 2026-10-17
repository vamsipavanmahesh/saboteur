# body_false

Replaces the whole body of a predicate method (one ending in `?`) with
`false`. A coarse whole-body mutant, generated instead of `body_nil` for
predicates: a predicate's `nil` is just `false`, so `true` and `false` are
the values its tests must reject. Skipped when the body is empty or only
logging. Fine-grained mutants run regardless of whether this one survives.

Runs by default. Use `--operators body_false` to select it alone, or
`--exclude-operators body_false` to leave it out. A survivor means no test
relies on the predicate ever being true - add the true case, or accept it
when the predicate is always false on the tested inputs.
