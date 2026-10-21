# Survivor ranking

`saboteur.findings` in JSON is fully ordered by this deterministic review priority. The terminal report groups survivors by file, method and line first (that grouping wins), and uses the same priority only to order the survivors on one line. The terminal prints one finding per statement by default - the label mix and mutant count, with the covering tests once; `--all-mutants` lists every mutant with its label:

1. Coarse (whole-body) survivors first.
2. More distinct recorded covering tests first. These tests passed without detecting the change, so they are leads for an assertion, not proof of a bug.
3. More distinct edited source lines first, a simple impact proxy.
4. Smaller distance from any edited line to a changed line in that file. An intersecting edit has distance zero. Without diff evidence the distance is unknown and ranks after known distances.
5. Relative file path, earliest edit line, then mutation digest break ties.

This is a heuristic, not a severity score. It does not infer runtime method visibility or assign speculative operator weights. Accepted survivors are listed separately in JSON. With `--all-mutants` the terminal lists every survivor, in review mode too. JSON findings remain bounded to ten entries per group. Ranking does not change generation, test execution order, scores, baseline identities or verdicts.

On one terminal line, only consecutive survivors with the same covering tests
(compared as a set, printed in the first mutant's run order), reuse status and
changed lines share an evidence block. If the same
evidence appears again after another group, it is printed again rather than
regrouping the mutants and changing their review priority.
