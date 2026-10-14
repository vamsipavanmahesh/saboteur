# condition_negation

Wraps an `if`, `unless`, modifier or ternary predicate in `!(...)`. Keeps the predicate evaluated once and preserves its grouping and branch structure. Does not mutate loops. Skips true, false and nil predicates owned by the existing constant operators, and existing `!`/`not` predicates owned by negation_removal. Arid expressions and nested definitions are skipped; the normal parser, dedupe and cap checks apply.

Runs by default. Use `--operators condition_negation` to select it alone, or `--exclude-operators condition_negation` to leave it out. Equal branch results can make a survivor equivalent; negation can also hide effects in a branch. Review the result and effects rather than assuming a survivor is a bug.

Committed fixture `conditions` adds two candidates: one killed by a branch-result assertion, one real missing-result survivor where the test checks only Integer type. No equivalent survivor is claimed in that fixture.

Inspired by mutineer's extra mutation operators (github.com/davidteren/mutineer, MIT, by David Teren).
