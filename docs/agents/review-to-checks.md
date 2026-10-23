# Review-to-checks loop

Run this task after every external review (see [reviewer.md](reviewer.md)).
It turns each finding into a permanent check, a lessons entry and a proposed
acceptance scenario - not just a one-off fix. The task text below is the
maintainer's, verbatim.

---

# Task: turn this review into permanent checks

Input: the review report at <path or pasted below>.

For each finding:
1. Classify the root cause: code bug, missing/weak test, fixture that passes by
   construction, overclaim, wiring tested only with doubles, sibling not swept,
   or plan written without checking existing behavior.
2. Append an entry to docs/lessons.md: finding, root cause, and the check that
   now prevents the whole class (not just this instance).
3. If an existing AGENTS.md rule should have caught it, explain why it didn't
   and tighten the rule, or replace it with an automated check. Prefer
   automation: a rule that keeps failing as prose becomes a CI check.
4. Propose a new acceptance scenario (fixture + expected result) in the PR
   description for the maintainer to approve. Do not add it to acceptance/
   yourself.
5. Then fix the finding itself, following AGENTS.md (e2e spec that fails on the
   parent commit, sibling sweep, measured CHANGELOG wording).

Finish with a summary: findings fixed, rules changed, checks added, and
acceptance scenarios awaiting maintainer approval.
