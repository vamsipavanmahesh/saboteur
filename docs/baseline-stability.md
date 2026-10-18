# Baseline stability check


Before looking up coverage or generating mutants, saboteur runs the unchanged
suite in separate supervised children with the run seed - two passes by
default, changed with `c.baseline_passes` or `--baseline-passes N`. Every pass
must succeed, execute every loaded test, and use the same test order. This also applies
when coverage and incremental verdict caches exist. A failed check stops the
run before any mutants start, names the seed and log file, and asks you to fix
the suite before trying again. Each check uses `coverage_timeout` and the suite
memory/process limits. Passing checks detect observed instability; they
do not prove that a suite can never be flaky. No subjects selected means no
mutation run and no baseline check.

Baseline children run `after_fork` for child setup, but do not call the
mutation-specific `before_fork` or `around_mutant` callbacks. The parent was
already prepared by normal boot (including the Rails disconnect step). Coverage
uses the same RSpec seed/order and refuses a failing suite instead of caching it.

## Time budget and the cold coverage build

With `--max-duration`, once the baseline passes are timed, a run whose
remaining budget cannot cover a cold coverage map build stops before building
it. The build costs about one more full pass and keeps nothing when it is cut
off. The stop names the shortfall and the remedies: a higher budget, fewer
`--baseline-passes`, or one unbudgeted run to warm the coverage cache for
later `--incremental` resumes (#427).
