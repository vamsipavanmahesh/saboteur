# Lobsters value ledger, final (supersedes the three-reading table in ../README.md)

Rubric as decided: presentation-only gaps (titles, meta tags, CSS, copy, decoration) are LOW even when they are the PR's own change. A gap is HIGH for the PR's own bug class only when the PR fixes a bug and the gap is wrong behavior. #2197 and #2157 are LOW. #2183 (traffic intensity) is LOW: the value only drives header presentation, not stored data. #2205 stays MEDIUM.

| value | gaps | mutants |
|---|---|---|
| high | 3 | 5 |
| medium | 2 | 8 |
| low | 7 | 39 |
| total | 12 | 52 |

Per-gap rows with one-sentence reasons are in `gap-values-final.json`. Noise (equivalent, false survivor, environment) is 0 gaps and 0 mutants and is reported separately; LOW is not noise. The earlier whole-suite completeness caveats still apply.

## Comment-worthy PRs (replaces within-PR ranking)
A PR is comment-worthy if it has at least one high or medium gap. Of the 13 assessed PRs: 4 would get a comment (2156, 2174, 2204, 2205) and 9 stay silent (2103, 2157, 2171, 2172, 2175, 2182, 2183, 2197, 2231). Of the silent ones, 5 have no live survivor (2171, 2172, 2175, 2182, 2231) and 4 have only LOW gaps (2103, 2157, 2183, 2197). #2178 and #2158 are not assessed yet and are outside these counts.

The within-PR ranking check is retired: native finding order is kept in `native-finding-and-score-evidence.json` as evidence only and is not a claim about value prioritization.

2103/2183 remains recorded as a coincidence, not a missed-bug hit (see ../README.md).
