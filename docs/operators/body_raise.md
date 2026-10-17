# body_raise

Replaces the whole method body with `raise`. A coarse whole-body mutant,
generated for every method whose own rescue clauses would not absorb it: a
raise the method itself rescues (a catch-all `rescue`, `rescue
StandardError` or `rescue Exception`) is suppressed by design, since
rejecting that exception is the rescue's contract. Fine-grained mutants run
regardless of whether this one survives.

Runs by default. Use `--operators body_raise` to select it alone, or
`--exclude-operators body_raise` to leave it out. A survivor means no test
observes the method raising where it should work - the missing case is the
method's normal effect, or every caller already handles the failure.
