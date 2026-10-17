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
  (a method defined inside a non-factory block, or in a file that uses
  refinements).
  `--agent` lists these as incomplete reasons with counts.

Read the score together with these counts. Whether two scores are comparable
is also a question of scope: a `--since` run, a `--subject` run and a full run
cover different mutants.


## Opt-in history

```sh
saboteur run --score-history .saboteur/score-history.jsonl
saboteur run --agent --score-history .saboteur/score-history.jsonl
```

The default is off. Each finished report appends one locked JSONL record with
version, UTC date, current commit (null outside Git), configured-selection and
mutant-inventory digests, score, coveredScore, counts, kill breakdown and
incompleteness reason codes. `score` stores the overall fraction defined above, including observed NoCoverage
mutants; `coveredScore` stores the engine's headline fraction. Subjects skipped
before mutation generation are not invented NoCoverage mutants. No history is written
for preview, invalid invocation or a run that failed before producing a report.
A later reporting failure can leave a history observation; history is not the
run's completion receipt, an incremental cache or a baseline gate.

The change since the previous record is printed to stderr in percentage points,
including agent mode so stdout remains exactly one JSON payload. A numeric change
requires identical configured selection and mutant inventory, complete records
and non-null scores. Otherwise it says the change is unavailable. Equal digests
do not prove equal coverage, environment, test content or test quality. History
is descriptive, not proof of improvement, and cannot replace baseline comparison.

Use the same file on successive runs to retain history. A fresh CI checkout has
no earlier record unless you restore one explicitly. Upload this JSONL file with
your own artifact step; the bundled Action does not upload it automatically.
No Action/workflow permissions or protected files are changed by this feature.
Malformed/truncated records and conflicting report paths fail loudly instead of
replacing old evidence. The history grows until you archive it yourself.

History/report destinations must be regular files without symlink components;
existing destinations must not share an inode. This is checked before the
engine runs and again before report writes. History reads use nonblocking
regular-file descriptors and a 64 KiB limit per JSONL record. Lock contention
has a two-second bound. Duplicate JSON keys and incomplete version 1 and
version 2 schemas are refused, with old bytes preserved. Total history can still grow; archive it.
A replay with `--id` records its one-mutant inventory, so it is not comparable
to a whole run. History is excluded from baseline/output fingerprints.
