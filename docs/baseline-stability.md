# Baseline stability check


Before looking up coverage or generating mutants, saboteur runs the unchanged
suite twice in separate supervised children with the run seed. Both runs must
pass, execute every loaded test, and use the same test order. This also applies
when coverage and incremental verdict caches exist. A failed check stops the
run before any mutants start, names the seed and log file, and asks you to fix
the suite before trying again. Each check uses `coverage_timeout` and the suite
memory/process limits. Two passing checks detect observed instability; they
do not prove that a suite can never be flaky. No subjects selected means no
mutation run and no baseline check.

Baseline children run `after_fork` for child setup, but do not call the
mutation-specific `before_fork` or `around_mutant` callbacks. The parent was
already prepared by normal boot (including the Rails disconnect step). Coverage
uses the same RSpec seed/order and refuses a failing suite instead of caching it.
