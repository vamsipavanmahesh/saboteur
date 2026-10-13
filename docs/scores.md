# Scores

One run reports several numbers that look alike. This page says what each one
counts, so two runs or two tools can be compared fairly.

## Counts that feed every score

| Status | Meaning | In the score |
| --- | --- | --- |
| killed | A test failed or crashed with the mutant applied | numerator and denominator |
| timeout | The suite ran past the timeout limit with the mutant applied | numerator and denominator |
| survived | Every test that ran passed | denominator only |
| error | The verdict did not hold up (a crash outside the test, a failed neutral check) | outside |
| resource limit | The mutant hit the memory or process cap | outside |
| skipped | Never run: no covering test, or a subject saboteur cannot re-evaluate | outside |
| ran at load | The code runs only at load, so no mutant can be judged | outside |
| unreachable | No test calls the replacement definition | outside |

A survivor accepted on the ignore list is still a survivor here. The ignore
list changes the exit code, not the score.

## Covered score

```
covered score = (killed + timeout) / (killed + survived + timeout)
```

This is the headline `score` in the terminal, the HTML page and `--threshold`.
It judges only mutants that ran. It is empty (no score) when none was tested.

## Overall score

```
overall score = (killed + timeout) / (killed + survived + timeout + NoCoverage)
```

NoCoverage is a mutant skipped with the reason "no coverage": no test runs
that code. Stryker-schema tools count it as undetected, so a dashboard that
reads the JSON report can show a lower number than the covered score for the
same run. The two agree when nothing lacks coverage. Saboteur's JSON report
does not store this number.

## Assertion and crash kills

A kill is an assertion kill when a failed check caused it, and a crash kill
when an error did (`NoMethodError`, `TypeError`, a parse error). A crash shows
the code ran and broke, not that a test looked at a value. The terminal prints
`score 100.0 % (assertion 50.0 %, crash 50.0 %)`. Each share is part of the
tested mutants, so the shares add up to the covered score. The split is shown
only when at least one kill has a recorded cause. A kill has none when its
verdict was reused from an older run, the test called `exit`, or the failure
was outside any example. When the split is shown, timeouts and kills with no
recorded cause get their own parts, but only if there are some.

## Without whole-body mutants

`body_nil`, `body_true`, `body_false` and `body_raise` replace a whole method
body. Almost any test that runs the method kills them. The second score line
(`saboteur.scores.withoutWholeBodyMutants` in the JSON) leaves them out, so it
says more about how well values are checked.

## When a run is incomplete

The score covers only the mutants that ran and gave a verdict, so a run can
score well and still say little. A run is incomplete when any of these hold:

- mutants errored or hit a resource limit. With `--threshold` the run exits 3,
  because the score covers only part of the run;
- more than half of the executed mutants errored. The run exits 3 with or
  without a threshold;
- subjects or mutants had no covering test, ran only at load, were unreachable,
  were left out by `max_mutants_per_method`, or were skipped as unsupported
  (a method defined inside a block, or in a file that uses refinements).
  `--agent` lists these as incomplete reasons with counts.

Read the score together with these counts. Whether two scores are comparable
is also a question of scope: a `--since` run, a `--subject` run and a full run
cover different mutants.
