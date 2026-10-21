# How to read survivors

A survivor is a mutant that every selected test passed against. This guide
walks one from the terminal output to the test that kills it. The example is
abridged from a run on the `people` fixture project (`spec/fixtures/projects/people`)
with saboteur 0.4.0 at main `6f704c8`. The digest and layout are illustrative:
digests depend on your source, and the terminal report layout can change
between versions, so compare the parts (subject, operator, digest, location,
diff, covering tests), not the exact text. Use a digest from your own run.


## Classification labels

The JSON report labels a survivor when a classification signal applies
(#192), most useful first. Every label is a heuristic - a hint about where to look first, not a diagnosis.
Inspect the survivor before acting; never add a test or ignore a mutant
from the label alone.

- `likely_equivalent` - the mutant compiles to the same instructions as
  the original: strong evidence of a no-op mutant. Check it against the
  source before treating it as equivalent.
- `arid` - every line an edit touches matches an arid pattern (logging
  and friends), so an assertion there is less likely to pay off. The
  builtin hint list decides; a configured arid policy does not change the
  label.
- `missing_test` - a test covered the line and passed, which may mean
  the suite reaches the code without pinning this behaviour. The covering
  list is only the planned coverage: whole-body (coarse) mutants carry
  method-level guesses and never get this label, and neither does
  anything without real coverage - a `--test-command` run records only
  the pseudo-test for every mutant, so its survivors never receive missing_test from pseudo evidence.

A survivor with no signal stays unlabeled - the field is omitted, never
empty. One label per survivor, first match in the order above. Labels
never change scores or the exit code. The label also shows as a badge
next to the survivor's status in the HTML report and as the
`classification` field on each shown finding in the agent JSON.

## Anatomy of a survivor

```
People::Person#adult? comparison <digest> lib/people.rb:14
--- a/lib/people.rb
+++ b/lib/people.rb
@@ -14 +14 @@
-    def adult?; @age >= 18; end
+    def adult?; @age > 18; end
2 tests covered this line and still passed (the missing check may belong in one of them):
  ./spec/person_spec.rb[1:1]
  ./spec/person_spec.rb[1:2]
```

- **Header:** the method (`People::Person#adult?`), the operator that made the
  change (`comparison`), the 16-character digest, and `file:line`.
- **Diff:** the original line (`-`) and the mutant (`+`). The mutant is what
  your code would do if someone made this edit by mistake.
- **Covering tests:** the tests whose line coverage touched this line and that
  still passed with the mutant applied. They are a heuristic lead, not proof:
  line coverage can overstate which tests exercise a line, and the missing
  check may belong in a test that is not on the list. The terminal shows five;
  the rest are under `coveredBy` in the JSON report.

In `--since` mode a survivor also prints `changed line: path:N`, the changed
line it relates to. Use that line, not `line`, when you look at the diff of
your pull request.

## Read it as a question

Ask: if the code really did this, would a caller notice? Here, `adult?` would
say a person aged exactly 18 is not an adult. The two covering tests check 17
and 19 (`spec/person_spec.rb`), so neither can tell `>= 18` from `> 18`.
That is a missing test here. The operator name is only a hint, not a verdict:
a `comparison` survivor often points at a boundary nobody tests, but it can
also be an equivalent mutant (for example when the value can never be equal).

The fix is the smallest test that fails against the mutant and passes against
the real code:

```ruby
it "is an adult at exactly 18" do
  expect(described_class.new(18).adult?).to be(true)
end
```

Run again. The mutant is now killed. To check one mutant without a full run,
replay its digest (see the [replay guide](replay.md)):

```sh
bundle exec saboteur run --id <digest>
```

For a longer list, `saboteur survivors .saboteur/report.json` (0.8.0+)
browses the report from the terminal: it lists and filters survivors
(`--ranked` for the ranked-findings order), and `--show <digest>` prints
the diff, the exact replay command and a ready ignore-file entry. It is
read-only: it never boots the project or edits the ignore list.

## What common operators usually mean

| Operator on the survivor | Usual cause | What to check |
| --- | --- | --- |
| `comparison` (`>=` to `>`) | an untested boundary | add a test at the boundary value |
| `literal_number` (`18` to `19`) | same boundary, or an unchecked constant | test the value on each side |
| `condition_false` / `condition_true` | no test takes one branch | add a test that takes the branch and asserts its result |
| `body_nil`, `body_raise` and other whole-body mutants | no test checks the method's result or effect | assert the return value or side effect |
| `argument_removal`, `pair_removal` | an argument or option nobody checks | assert that the argument changes the outcome |

A surviving whole-body mutant is a strong hint that no selected test checks
the method's result or effect. It is a heuristic, not proof. Before you write
a test, check these cases:

- The method may return `nil` (or another value) on purpose, so replacing the
  body with `nil` changes nothing a caller can see.
- The mutant may be equivalent for the inputs the code can receive.
- The method may be part of a protocol or contract (a hook, a callback, a
  `to_s`, a no-op default) that callers rely on only through another class.
- Its effect may be observed in a test that was not selected for this line.

## Survivor, no coverage, or skipped

- **Survivor:** a test ran the line and passed. Write or tighten a test.
- **No coverage:** no test reached the line, so it is not a survivor. The
  summary prints `mutant locations not reached: N`. Write a test that runs the code
  first; mutation says nothing useful until one does.
- **Other statuses** (timeout, error, resource limit) do not count as
  survivors. See the README for how each one is scored.

## When not to write a test

Accept a survivor only when you can say in one sentence why no test could
tell the two versions apart. Common reasons:

- **Equivalent mutant.** The change does not alter behavior (for example a
  loop bound that is never reached because a list is capped). Accept it on the
  ignore list with a reason that a reviewer can disagree with.
- **Flaky or order-dependent tests.** Fix the test first; see
  [best practices](../best-practices.md#flaky-test-hygiene).
- **A limit of the tool.** Report it and ignore the entry with a reason that
  says so.

An ignore entry needs a reason; one without a reason is rejected. See
[Handling surviving mutants](../best-practices.md#handling-surviving-mutants)
for the ignore file format.

## Reading the score next to survivors

The score line splits kills into assertion kills (a test checked a value) and
crash kills (the code raised). A score made mostly of crash kills suggests that
many tests only notice a mutant because the code raised, not because they
checked a value. That is a lead to look at, not a guarantee: a test that
asserts on a raised error or a custom contract is a legitimate crash kill. The line
`score without whole-body mutants` removes the easy kills; read that one when
the headline score looks too good.
