<!-- Provenance: methodology contract authored by the study lead and handed to the merger lane 2026-10-24 08:22 IST. Adopted verbatim; it supersedes and extends the 08:21 metric summary previously in this file (decision D3/D7 in DECISIONS.md). This is a method document, NOT results; no study rate is available until the stored records are verified. -->

# Field-study metric contract

Decision snapshot: October24,2026,08:22IST. Counts are produced from stored records, not this document. No study rate is available until those records are verified.

## Noise and triage

Unit: one unique unignored surviving mutant per app/PR/report run designated as authoritative. Do not count repeats, parallel runs, or earlier superseded reports twice. Preserve all raw reports. Four resolved classes: real_gap, equivalent, false_survivor, environment_noise. Unresolved stays unresolved, not noise and not real_gap.

Noise numerator = equivalent + false_survivor + environment_noise. Denominator = all independently resolved survivors. Always report total survivors, resolved and unresolved, triage coverage, four class counts, and the per-PR counts. Empty denominator => null/N/A, never0%.

For incomplete triage, report descriptive resolved-only noise plus total-survivor bounds: noise/total through(noise+unresolved)/total. These are unresolved-case bounds, not confidence intervals. Never call a partial result final.

Primary95% interval: seeded PR-cluster percentile bootstrap of the ratio of pooled noise counts to pooled resolved counts,10000 resamples with replacement of the eligible selected PR rows, seed20261024. Retain zero-survivor PRs as clusters. Reject zero-denominator resamples and report their count; fewer than2 informative PR clusters => interval N/A. Label exploratory small-sample interval, conditioned on this PR selection and resolved labels, not guaranteed population coverage. Publish sorted bootstrap values or sufficient input/script/seed for exact recomputation.

Supplemental95% Wilson interval may be shown as descriptive per-mutant binomial interval, explicitly not accounting for within-PR correlation. Do not use it as stronger evidence than the cluster-aware interval. No interval addresses untriaged cases or selection bias.

## Top-ranked finding

Use report.json saboteur.findings.order, first live unignored survivor. Preserve top digest, statement-group mutant IDs, path and edited span, original tool label, independent class and evidence. Tool labels are not independent classification. No live survivor => N/A. Unresolved top finding => unresolved, not false. Report top1 real-gap count over PRs with independently resolved top findings; also give denominators over all15 selected PRs and number with no finding/unresolved/blocked.

## Verified bug replay

Keep candidate/fix/introducer eligibility ledger even for skips. Up to20 candidate fixes per app chosen by declared reproducible rule at frozen timestamp. Six-month window anchored to original October24,2026 request: April24,2026 through collection cutoff, exact timestamp/date convention recorded. Use merged_at for PR eligibility and committed timestamp for introducing commit age; preserve authored and committed timestamps if different. No associated PR returned does not prove direct push.

Eligible completed bug replay denominator excludes skipped/blocked/unverified cases, which are reported separately. Required verification: immutable introducing parent/head and fix parent/head, line mapping, regression test fails before fix and passes after, historical introducing tests used for saboteur run, baseline/maps/cache-restore proof, authoritative report.json, fake-kill check, exact source version/SHA and app runtime/DB, raw timing/RSS/exits.

HIT: at least one live survivor's actual mutation edited span intersects the fixed-line set mapped back into introducing-head coordinates. No proximity allowance. Use actual edit ranges rather than whole-subject span. Boundary convention: one-based inclusive lines; derive end from exclusive byte end-1, preserving raw positions. For ambiguous mapping/multi-bug fix, mark unresolved; do not force HIT/MISS. Preserve mapping provenance. MISS only after an eligible completed report with no intersection, assigned evidence-supported reason: not_mutated_class_body_DSL, out_of_scope, no_operator, wrong_behavior_encoded_by_tests, other. Unverified/no report is not MISS.

Per-app hit rate=HIT/(HIT+MISS), with skipped/blocked/unresolved counts. Bootstrap by introducing PR cluster if multiple verified bugs share a PR; small sample N/A as above. Store each entry under bugs/<app>-<full-fix-sha>/, and distinguish multiple bug records in one fix directory.

## Flag rate / chance context

For each introducing PR, denominator is unique added/modified head-coordinate Ruby lines in app/ or lib/, including changed blank/comment/DSL lines; do not silently limit to executable/mutable lines. Deleted old-coordinate lines are recorded separately, excluded from this denominator. Preserve full diff/line sets and alternate counts for recomputation.

Numerator is denominator lines intersected by any live survivor's actual mutation edit span. Deduplicate line numbers across mutants; do not flag an entire method because one coarse edit exists elsewhere. Flag rate=numerator/denominator; zero denominator => N/A. Aggregate both pooled-line rate and mean per-PR rate, with denominator names. This is a location baseline, not a causal chance-hit probability: fixed bugs and changed lines are not uniformly random, and spans vary. Do not claim detection better than chance merely because hit rate exceeds flag rate.

## Readiness and honest zeroes

Selection15 means latest15 eligible merged PRs at frozen live cutoff, descending merged_at with stable PR-number tie-break; no old-pin ancestry filter or convenience replacement of blocked rows. Store fetched candidate pages, rule, eligible list and every skip. Preserve zero-mutant results as zero-mutant, scoreN/A, not coverage success. All survivors uncapped for expanded study. Evidence incomplete => no final metric. Fake-kill check before any score, and known-red credit => stop affected run, record finding and route decision.
