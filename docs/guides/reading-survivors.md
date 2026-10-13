# How to read survivors

A survivor is a mutant that every selected test passed against. This guide
walks one from the terminal output to the test that kills it. The output below
is a real run on the `people` fixture project.

## Anatomy of a survivor

```
People::Person#adult? comparison f5f5bc39bd01444f lib/people.rb:14
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
  still passed with the mutant applied. They are a lead, not proof: line
  coverage can overstate which tests exercise a line. The terminal shows five;
  the rest are under `coveredBy` in the JSON report.

In `--since` mode a survivor also prints `changed line: path:N`, the changed
line it relates to. Use that line, not `line`, when you look at the diff of
your pull request.

## Read it as a question

Ask: if the code really did this, would a caller notice? Here, `adult?` would
say a person aged exactly 18 is not an adult. The two covering tests check 17
and 19 (`spec/person_spec.rb`), so neither can tell `>= 18` from `> 18`.
That is a missing test, and the operator name already hinted at it: a
`comparison` survivor is usually a boundary nobody tests.

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
bundle exec saboteur run --id f5f5bc39bd01444f
```

## What common operators usually mean

| Operator on the survivor | Usual cause | What to check |
| --- | --- | --- |
| `comparison` (`>=` to `>`) | an untested boundary | add a test at the boundary value |
| `literal_number` (`18` to `19`) | same boundary, or an unchecked constant | test the value on each side |
| `condition_false` / `condition_true` | no test takes one branch | add a test that takes the branch and asserts its result |
| `body_nil`, `body_raise` and other whole-body mutants | no test checks the method's result or effect | assert the return value or side effect |
| `argument_removal`, `pair_removal` | an argument or option nobody checks | assert that the argument changes the outcome |

A surviving whole-body mutant is the strongest signal: the method's behavior
is not pinned at all.

## Survivor, no coverage, or skipped

- **Survivor:** a test ran the line and passed. Write or tighten a test.
- **No coverage:** no test reached the line, so it is not a survivor. The
  summary prints `skipped: no coverage: N`. Write a test that runs the code
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
crash kills (the code raised). A high score made mostly of crash kills means
tests run the code but do not check results. The line
`score without whole-body mutants` removes the easy kills; read that one when
the headline score looks too good.
