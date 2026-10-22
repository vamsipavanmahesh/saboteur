# Reading a survivor report and fixing survivors

A survivor is a mutant your suite let live. This guide walks a real batch
from report to clean exit, using the output of an actual 0.7.0 run on
[publify](https://github.com/publify/publify), a public Rails app. The
one-survivor anatomy is covered piece by piece in
[How to read survivors](reading-survivors.md); this is the working loop for
a report with several.

The run: a PR branch adding `AuthorsSidebar#enough_authors?` with one
happy-path spec, checked with the `pr` preset. The
[CI guide](ci-pull-request.md) has the full setup.

## 1. Read the summary first

```
saboteur 0.7.0: 2 subjects, 12 mutants, wall 9.97 s, seed 1 (repeat with --seed 1)
killed 8  survived 4  timeout 0  resource limit 0  error 0  skipped 0
score 66.7 %
```

Exit code 1, four survivors. The score counts `killed / (killed + survived)`
- timeouts count as killed; errors, skips and resource limits do not count
at all.

## 2. Group the survivors by what they say

```
Survivors (4):

  AuthorsSidebar#enough_authors?
      15: authors.size >= count_threshold
      - body_true authors.size >= count_threshold -> true 0f5efe2878b091c3
        hint: try asserting this method's result or its effect
      - comparison >= -> == 6ce4cca2711d005e
        hint: try an example at the boundary: equal values, or values one apart
  AuthorsSidebar#count_threshold
      19: 2
      - literal_number 2 -> 0 6ab8abe5666c800f
        hint: try asserting something that depends on this number
      - literal_number 2 -> 1 964d0e82a1c63726
        hint: try asserting something that depends on this number
```

All four survivors are one sentence: *the suite never checks the boundary.*
`body_true` says the predicate's false case is untested, `>= -> ==` says the
exact-boundary case is untested, and the two `literal_number` survivors say
the threshold value itself is untested. Four mutants, one missing behavior:
what happens with one author, and with more than two.

Not every survivor is a missing test. The same block can carry an
equivalent mutant (the change alters nothing observable) or dead code.
Hints are suggestions: confirm against your own code before writing a test.

## 3. Cross-check in the JSON report

Every run writes `.saboteur/report.json` (and an HTML twin). Each mutant
carries its digest, operator, replacement, location, status and the tests
that covered it:

```json
{
  "id": "6ce4cca2711d005e",
  "mutatorName": "comparison",
  "replacement": "==",
  "location": { "start": { "line": 15, "column": 5 }, "end": { "line": 15, "column": 36 } },
  "status": "Survived",
  "coveredBy": ["0"],
  "duration": 315
}
```

Survivors also carry a `classification` (`likely_equivalent`, `arid`, `tool_limit`,
`input_gap`, `assertion_gap`, or a gap kind such as `boundary`) when a heuristic matches - a triage-order
hint that never changes the score or the exit code. None fired on this batch; the terminal
hints were the only guidance, and they were right.

## 4. Fix with tests, not edits

The rule: never change production behavior only to kill a mutant. Here the
mutants exposed real missing behavior, so the fix is two specs:

```ruby
it "does not have enough authors with a single active author" do
  User.where.not(id: authors.first.id).delete_all
  expect(sidebar.enough_authors?).to be(false)
end

it "has enough authors when three are active" do
  create(:user)
  expect(sidebar.enough_authors?).to be(true)
end
```

The one-author case kills `body_true`, `literal_number 2 -> 1` and
`2 -> 0` (with one author, a threshold of 1 or 0 flips the answer). The
three-author case kills `>= -> ==` (3 is `>= 2` but not `== 2`).

## 5. Replay the digests, then rerun

You do not need a full run to check the fix. The run's Next steps print a
replay command per survivor with every setting baked in:

```sh
bundle exec saboteur run --id 6ce4cca2711d005e --since origin/master \
  --test spec/models/authors_sidebar_spec.rb --operators '' --exclude-operators '' \
  --baseline-passes 1 --max-duration 600.0 --max-duration-ok --seed 1
```

```
Selected tests:
  ./spec/models/authors_sidebar_spec.rb[1:2:4]
  ./spec/models/authors_sidebar_spec.rb[1:2:3]
  ./spec/models/authors_sidebar_spec.rb[1:2:5]

Replay: AuthorsSidebar#enough_authors? comparison 6ce4cca2711d005e (killed)
```

The coverage map re-recorded on the fly, and the new specs joined the
selected set. Then the confirming full rerun:

```
saboteur 0.7.0: 2 subjects, 12 mutants, wall 10.07 s, seed 1 (repeat with --seed 1)
killed 12  survived 0  timeout 0  resource limit 0  error 0  skipped 0
score 100.0 %
```

Exit 0. [Replay one mutant](replay.md) covers digest replay in depth.

## False survivors in a scoped run

`--since`, `--subject` and the default spec inference run only the specs
they select. A survivor can be killed by a spec outside that selection,
for example an integration spec with no matching source file. Only
`saboteur run --all` builds the whole-suite coverage map that names those
specs. Without that map a scoped run prints one line, `survivors
unconfirmed: no whole-suite coverage map; run `saboteur run --all` to
build one`, and each survivor block says the covering list is this run's
selection only. Verdicts, score and exit code do not change.

With the map, each surviving mutant also gets one budgeted confirmation run
of its covering specs the run did not load (the budget is `confirmation_budget`,
300 seconds by default; no flag). A mutant those specs kill becomes killed,
credited to the killing test in the JSON report (`confirmation:
killed_by_confirmation`, `creditedTest`), and counts in the score and the
exit code. A survivor whose covering specs could not be run (budget spent, or
the run failed) is listed under "unconfirmed (covering tests not run)",
reported as `confirmation: unconfirmed` with status `Ignored`, and is left out
of the score and the exit code. A failure while confirming prints one warning
and never ends the run.

When the map is older than the tree, it may say nothing about a survivor's
lines (added or shifted since `run --all`). That survivor stays counted in the
score and the exit code, shows `confirmation: unconfirmed` without being
ignored, and the run prints one line naming how many; rebuild the map with
`saboteur run --all`. The map is read as untrusted: a covering spec outside
the project root (symlinks resolved) is never loaded, and a map that names one
is refused: its survivors stay counted and the run prints one warning.

## 6. When the fix is not a test

If a survivor is genuinely equivalent - the mutation cannot change any
observable behavior - accept it with a reason instead of contorting a test:

```ruby
# config/saboteur_ignore.rb
Saboteur.ignore do |i|
  i.mutation "0f5efe2878b091c3",
             subject: "AuthorsSidebar#enough_authors?",
             reason: "equivalent: the predicate is always true on this path"
end
```

An ignored survivor stops failing the run but still counts in the score,
and an entry without a reason is rejected. Unreleased on main (coming in
0.7.1): entries carry a triage `state:` - `accepted_equivalent` (default),
`wont_fix` (also suppresses the exit failure), or `todo` (records the
decision and keeps the survivor counting) - badged in the HTML report.

The order of operations never changes: read, decide missing-test vs
equivalent, fix with a test or accept with a reason, replay, rerun.

The ignore list is the one place to accept; the inline `saboteur:disable-line`
directive and `baseline accept` are advanced paths, framed in
[Handling surviving mutants](../best-practices.md#handling-surviving-mutants).
