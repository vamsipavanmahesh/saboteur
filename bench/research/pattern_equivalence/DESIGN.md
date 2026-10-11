# Pattern-based equivalence spike: design and pre-registered decision rules

Status: written and committed before any measurement run. The commit order
is the evidence. Research only: everything lives under
`bench/research/pattern_equivalence/`, no engine or `lib/` change.

## Question

What share of builtin-generated mutants (and of surviving mutants) can a Prism
pattern matcher mark behavior-equivalent, with zero matched mutants that a
test suite kills? The earlier bytecode spike (`bench/research/trivial_equivalence`)
matched 0 of 9,178 mutants. This spike tests whether narrow source-level
patterns do better. It makes no claim about the bytecode result.

## Soundness boundary (stated up front)

A match is a claim "behavior-equivalent modulo redefinition of core classes
and operators". It is unsound if the code under test reopens Integer, Float,
Array, String or NilClass, defines `method_missing` or refinements on a
literal's class, or uses ObjectSpace, TracePoint or binding tricks. The matcher
refuses (no verdict) for every file of a workload when a project-wide scan finds
any of these. Per-file refusal is not enough, because another file can reopen
a class this file uses.

"Pure" means: a literal, a local variable read, an instance variable read,
`self`, or a constant read. A method call is never pure. Anything not provably
pure gives no verdict. The matcher outputs "matched" or "no verdict", never
"not equivalent".

## Pattern catalogue

Inputs per mutant: the original Prism node, the edit range and the
replacement text. Each pattern lists the conditions under which it would be
unsound; the matcher must refuse in those cases, and each condition has a
must-not-match spec.

- **P0 No-op edit.** The replacement text equals the original slice. Unsound:
  never, except that the edit changes the parse (re-parse check).
- **P0b Duplicate.** Two mutants give byte-identical full file text. This is
  de-duplication, not equivalence. Reported separately, counted once.
- **P1 Unreachable code.** The edit lies after an unconditional `return`,
  `raise`, `break`, `next`, `redo` or `throw` in the same statement list. The
  terminator must be a keyword node or a bare `raise`, must not be nested in a
  conditional, and no `ensure` or `rescue` may wrap the dead span. Unsound if a
  rescue or ensure re-enters the span, or the terminator name is redefined.
  Reported separately from coverage: coverage selection may already skip these.
- **P2 Dead local store.** `statement_removal` of `x = <pure>` where x has no
  read anywhere in the method, is not captured by a block, the method has no
  `binding`, `eval` or `local_variables`, and the statement is not in value
  position (the removal replaces it with `nil`, so a last statement or a branch
  value that is used would change). Unsound if the RHS is a call.
- **P3 Memoization on a fresh local.** `x ||= v` to `x = v` where x has no
  earlier assignment on any path, is not a parameter or pattern or rescue
  binding, and the node is not inside a loop or block body that re-runs with x
  declared outside it. Then x is nil there and both forms are identical.
- **P4 Safe navigation on a provably non-nil receiver.** `a&.b` to `a.b` where
  the receiver is `self` or a non-nil literal (string, array, hash, number,
  symbol, regexp, range). Locals are out of scope for this version. Not matched:
  `X.new` (`new` can be overridden), constants (can be nil).
- **P5 Folding of comparison and arithmetic on literals.** Both operands are
  numeric literals; evaluate original and mutant and match when the results are
  `eql?` with the same sign for zero. A raise (for example `1/0`) is a value,
  compared by class and message. Unsound if Integer or Float is reopened.
  Expected tiny; kept as a calibration pattern.
- **P6 Boolean identity-element operand.** `true && b` to `b` and
  `false || b` to `b` in any context. In a boolean context only (predicate of
  if, unless, while, until, ternary, or `!`): `b && true` to `b`, `b || false`
  to `b`, `b && false` to `false` and `b || true` to `true` when b is pure, and
  `a && a` to `a` when a is pure and textually equal. Unsound if the context
  uses the value, b has side effects, or precedence changes the parse.
- **P7 Branch-insensitive condition.** `condition_true` or `condition_false`
  on an if, unless or ternary whose predicate is pure and whose branches are
  byte-identical or both empty.
- **P8 Trap: `x * 1` to `x / 1` and back.** Subsumed by P5 for literal
  operands. `x + 0` to `x - 0` is deliberately NOT matched (`-0.0 + 0` is
  `0.0`, `-0.0 - 0` is `-0.0`). Expected: 0 matches. It exists so the panel can
  check the matcher's rigor.

Explicitly not patterns: relational swaps such as `<` to `<=`,
negation_removal, `literal_number` on numbers, and anything needing type
inference. That is the type-dependent frontier and the reason a small share is
expected.

## Measurement plan

Workloads: hashie, saboteur itself, lobsters. For each:

1. Generate all builtin mutants (same enumeration as the bytecode spike). Log the
   count per operator. Record seed, revisions and Ruby version.
2. Run the matcher without executing tests. Record pattern id and verdict per
   mutant, keyed by the stable mutation digest.
3. Verdicts for the full set come from the saboteur engine's own run
   (coverage-selected tests), joined by digest. A naive per-mutant full-suite
   loop is not feasible for saboteur itself (about 70 s per suite run). For
   lobsters the verdicts come from the benchmark pack's run of the same
   engine, and lobsters results follow the pack's data. If the pack covers
   only part of the matched mutants, the report says partial and marks the
   remainder static-only.
4. **Every matched mutant is also run against the FULL suite**, so a kill by a
   test the engine did not select is not missed.
5. Metrics per pattern and workload: matched count; matched share of all
   mutants; matched share of survivors; matched-and-uncovered versus
   matched-and-covered survivor; P0b counted separately; score change if
   matched mutants left the denominator (before and after, both shown).
6. Kill accounting: matched mutants the suite killed. Any kill means the
   pattern is unsound or the suite observes redefinition: stop and root-cause.
   Timeouts are counted separately (not evidence either way). Report 0/n with
   the rule-of-three 95% upper bound (3/n). Do not say "sound". Say "no
   counterexample in n".
7. Manual audit (the suite can only reveal unsoundness): per pattern, a seeded
   random sample of up to 30 matched mutants (all if fewer), each labeled
   independently by two reviewers reading the actual diff. Any disagreement
   disables the pattern. Plus a seeded sample of 100 unmatched survivors per
   workload labeled equivalent, not equivalent or unclear, to estimate recall.
   The unclear bucket is reported, not folded in.
8. Cross-check with the bytecode spike: of pattern-matched mutants, how many had
   identical bytecode (expected about 0), and of audit-equivalent mutants, how
   many had identical bytecode.

## Pre-registered decision rules

A pattern is recommended for the engine only if all hold:

- (a) zero matched kills across all workloads with data;
- (b) the manual audit has zero disagreements;
- (c) the matched share of survivors is at least 1% on at least one workload, or
  the pattern is cheap enough to be free.

Otherwise it is recorded as a measured negative. A low single-digit share, or
zero, is an acceptable result.

## Threats to validity

- Suites with weak oracles leave non-equivalent mutants alive, so survivors
  overstate equivalents. The audit corrects the recall estimate, not the matcher.
- The same suite validates and measures; kill accounting only sees
  unsoundness the suite can observe.
- Three workloads, one Ruby version (3.3.6); lobsters' metaprogramming may trip
  the core-class-reopen refusal.
- Builtin mutants only.
- Reviewer 2 in the audit is a panel lens on the pull request, not an
  independent author of the matcher.
- Lobsters verdicts come from a different run (the pack) and arrive later.

## Deliverables

`bench/research/pattern_equivalence/`: matcher, measure script, audit sheets,
`results.json`, `REPORT.md`. Draft pull request on first push. No `lib/` or
README change unless a pattern clears the rules, and then in a separate pull
request.
