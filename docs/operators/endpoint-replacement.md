# Collection endpoint replacement

The new builtin source swaps `receiver.first` and `receiver.last` when the call
has no arguments or block. It changes only the message bytes. It catches the
wrong end being chosen from an ordered collection, which may otherwise keep
all types and control flow unchanged. Existing comparison/boolean/arithmetic
operators do not change this message selection.

Both direction specs use a two-element ordered list and prove an assertion
kills the emitted mutant. Empty/singleton lists can make it survive; that is
not evidence of equivalence on other inputs. Tests that assert only non-nil
or membership can miss it.

## Historical motivation, not reproduced-fault claims

We inspected Ruby/Rails ordering bug fixes before choosing the family:

- Rails #24131 fixes asymmetric `first`/`last` behavior under `limit`, adding a
  guard around primary-key ordering. The defect is an ordering-policy guard,
  not a direct wrong-message swap. Our operator can probe caller expectations
  about endpoints, but we do not claim it recreates or detects this specific
  framework defect.
  https://github.com/rails/rails/pull/24131
- Rails #54608 adds errors for order-dependent finders without usable order
  columns. It further establishes that endpoint selection has a stronger
  ordering contract than arbitrary element selection. Again, the new mutation
  is not presented as that patch's exact defect.
  https://github.com/rails/rails/pull/54608
- Ruby's Array API documents first/last as opposing endpoints, including the
  argument-bearing array forms. We deliberately exclude those forms in this
  first bounded family, avoiding return-shape and slice-size combinations.
  https://docs.ruby-lang.org/en/3.4/Array.html

No external operator implementation was consulted or copied. The implementation
uses the existing public byte-edit API and independent specifications.

## Limits and safety

No static receiver type is inferred. Custom classes may implement either name,
and a missing opposite method can cause a crash kill. Reports already separate
crash and assertion kills; a crash is not claimed as stronger test quality.
Safe navigation stays in place. Bare calls, calls with arguments or blocks,
arid statements and nested scope definitions are not mutated. Deterministic
source traversal and relative-byte digests preserve repeatability.

This increases the generated inventory, so integration totals must be measured
again, never adjusted just to make CI green. Baselines include the saboteur
version/generator compatibility and should be recreated after operator changes.

## Measured integration inventory

Ruby 3.3.12/Linux, pinned integration/targets.yml checkouts, unchanged target
suites, seed from integration configuration:

- dry-inflector nesting: 530 killed / 24 survived / zero error, timeout or skip.
  Before this family: 527 killed / 24 survived. The three extra endpoint
  mutants all receive killed verdicts.
- dry-inflector class_eval: 522 killed / 23 survived / 9 errors / zero timeout
  or skip. Before: 519 killed / 23 survived / 9 errors.
- tty-color nesting: 138 killed / 26 survived / zero error, timeout or skip,
  unchanged. class_eval: 80 killed / 71 errors / 13 survived / zero timeout or
  skip. Its historical stable gate remains killed+error=151, not the variable
  individual split.

Commands: `script/integration-target NAME /tmp/endpoint-targets --reeval
STRATEGY` for both targets and both strategies. This is inventory validation,
not a speed claim or measured real-fault detection benchmark. macOS inventory
still needs CI validation; it is not inferred from these Linux runs.
