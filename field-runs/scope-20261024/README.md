# Scope 2026-10-24: reduced selections and value analysis (analysis and selection only)

No new study runs, mutation results or merges are recorded here. Everything below is a selection or an analysis of existing results.

## Scope
- Lobsters: 13 PRs assessed plus the last 2 (13/15 assessed so far).
- Chatwoot and Human Essentials: 10 noise PRs each, chosen as the first 10 of the earlier ordered qualification, with no re-qualification and no backfill.
- Missed-bug replay: 10 bug-fix PRs per app (goal 30 total). The lists below are CANDIDATES (classifier signals), not verified bugs. The goal of 10 verified bug fixes per app is NOT met by these lists.
- All execution is intended for GitHub runners.

## Contents
- `chatwoot/noise-selection-10.json`: noise PRs 16092, 15761, 16094, 16358, 16208, 16093, 16266, 16329, 16281, 16328.
- `chatwoot/bug-candidates-10.json`: candidates 16092, 16385, 16374, 15761, 16247, 16094, 16358, 16208, 16093, 16266. Enterprise-heavy PRs replay only the CE portion; per-PR counts are in the files. `field-runs/apps/chatwoot/selected_prs.json` is a stale earlier 5-PR list and is not this population (see `chatwoot/STALE-selected_prs.md`).
- `he/`: noise PRs 5723, 5742, 5656, 5727, 5541, 5722, 5386, 5274, 5171, 5606; bug candidates 5743, 5723, 5742, 5656, 5727, 5541, 5722, 5709, 5602, 5695 (`selection-v4-scope10.json`). Ledger of the 10: 5 age-skipped, 4 pending regression witnesses (5723, 5742, 5656, 5722), 1 unresolved mapping (5709); zero verified bugs, zero denominator inclusions. `triage-schema.json` defines the value rating (high/medium/low plus one sentence) kept separate from the equivalent/false classification.
- `lobsters/`: proposed value rating per gap (`gap-values.json`), native finding order and scores copied without re-ranking, and `summary-and-native-ranking.json`.

## Lobsters value analysis (proposed, rubric precedence pending)
12 independently unit-proved gaps, 52 surviving mutants. Equivalent 0, false survivor 0, environment noise 0 (same selection and completeness caveats as before). Low value is NOT noise. Eight no-coverage and six ignored mutants are outside this denominator.

Whether a missing-title or metadata change counts as LOW (title/meta) or HIGH (the PR's own bug class) is unresolved, so the distribution is shown under each reading:
| reading | HIGH gaps/mutants | MEDIUM | LOW |
|---|---|---|---|
| title/meta always LOW | 4 / 10 | 2 / 8 | 6 / 34 |
| 2197 missing-title bug counted as own-bug-class HIGH | 7 / 32 | 2 / 8 | 3 / 12 |
| and 2157 metadata also HIGH (extra assumption) | 8 / 38 | 2 / 8 | 2 / 6 |

Ranking: 8 PRs have live survivors; 5 of 13 have none (2231, 2171, 2182, 2175, 2172), so ranking is N/A there. Within a PR the survivors are all one value tier, so "high first" is satisfied only vacuously and does NOT demonstrate value prioritization. Native order is review priority, not a value sort.

## 2103 / 2183
Recorded as a coincidence, not a missed-bug hit. 2103's source contains `Rails.cache.fetch` in `cached_current_intensity` and the 2183 diff removes that wrapper, but no `cached_current_intensity` mutant appears in any published 2103 report, so no 2103 flag or rank is established.

## Not done / not proven
Hosted missed-bug witness and introducing-PR lanes are not implemented. Native doctor/map/replay for HE and Chatwoot have not run. `he/` and `chatwoot/` ledgers have no completed rows. Bug-ledger key `correction_0849` was renamed mechanically from an internal label; contents otherwise as received.
