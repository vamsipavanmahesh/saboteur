# Pattern equivalence: bounded negative spike

2026-10-12. Research only. No mutants are suppressed by this code.

## Decision

Do not ship a source-pattern skip into the engine. The strict subset tested found
zero matches among 12,901 generated mutants from three pinned Ruby projects.
That is measured reach of zero for the implemented subset, not proof that every
pattern in the proposed P0-P8 catalogue has no value. No equivalent-mutant recall,
suite-kill false-positive rate or performance benefit is claimed.

## Implemented subset

- P0: byte-identical edited method text. This is already handled by generation's
  unchanged/duplicate checks; duplicate text is counted separately, not labelled
  equivalent.
- P6: `true && expression` or `false || expression` replaced with its right
  expression. The right side still evaluates, and return-value semantics agree
  in ordinary evaluation. This is a syntactic research candidate only: source
  introspection, TracePoint/debugging and instruction observability are outside
  the contract. It is not unconditional Ruby behavioral equivalence.

Each implemented pattern has positive tests and deliberate nonmatches. The
matcher checks exact Prism node/edit bounds; it does not execute tests or target
code. An initial range matcher that selected a wrapping StatementsNode was
caught by the positive fixture and fixed before measurements were retained.

## Measurements

Ruby 3.3.12, Linux, Prism from repository bundle. All `lib/**/*.rb` files are
parsed and every def's current builtin mutants generated, without coverage/caps.
Counts are pre-dedup generation counts, not executed denominators or scores.

| Project | SHA | Subjects | Generated | Invalid method text | Duplicates | Pattern matches |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| saboteur | 2511035 | 810 | 12,151 | 6 | 341 | 0 |
| dry-inflector | b6a2819f0cf1bc0c24e024bbdf73f4f67003cbc9 | 40 | 573 | 0 | 1 | 0 |
| tty-color | e2410967c13e0d3e2297456db22495cb246b22f5 | 17 | 177 | 0 | 13 | 0 |

All files parsed. No full file mutation, nested runtime semantics or target
boot is validated by the method-text parser. Raw results are in results.json.

Reproduce from saboteur's root with `bundle exec ruby
bench/research/pattern_equivalence/measure.rb PROJECT_ROOT`. Check out each
listed SHA first. The two public MIT gems are the pinned integration projects,
not the originally proposed hashie/lobsters workloads; those historical
worktrees were unavailable in this run. This change of sample prevents any
claim that the original preregistered three-workload experiment is complete.

## Catalogue audit and rejected assumptions

P1 unreachable edits, P2 dead local stores, P3 fresh-local memoization, P4
nonnull safe navigation, P5 numeric folding, P6 broader boolean identities,
P7 identical branches and P8 numeric arithmetic identities remain unimplemented.
They are not enabled by zero matches in this strict subset.

A local/ivar/constant read is not a general purity proof in Ruby. Bindings,
closures, TracePoint, source inspection, overridden numeric methods, refinements,
exceptions and control-flow contexts must be handled explicitly. In particular
unused assignments can be visible through `binding.local_variable_get`, and a
statement's removal can change a method's return. `x + 0` versus `x - 0` must
retain signed-zero behavior; two survivors are not proof of equivalence.

There are no matched candidates to run against suites or send to independent
semantic audit. Report 0 matches, not 0 false positives in 12,901: the latter
would misstate the false-positive denominator. No rule-of-three estimate follows
from an empty matched population. No engine skip can be justified here.

## Next decision

The bounded spike ends with a measured no-ship result. Expanding the catalogue
or finishing the original workload/manual-audit plan is separate research, not
unfinished product suppression. Prefer better tests and explicit survivor
acceptance until a pattern has a documented semantic boundary, independent
adjudication and a nonzero useful matched population.

## Source notes

- Ruby 3.4 operators documentation: logical operators short-circuit and return
  the last evaluated expression, not necessarily a boolean:
  https://docs.ruby-lang.org/en/3.4/syntax/operators_rdoc.html
- Binding documentation: local variables can be read and changed reflectively:
  https://ruby-doc.org/3.4/Binding.html
- Ruby control-expression documentation: predicates may have side effects and
  modifier/normal forms can differ by parse-order binding:
  https://ruby-doc.org/3.4/syntax/control_expressions_rdoc.html
