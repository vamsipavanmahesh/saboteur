<!-- Provenance: bug outcome unit and multiple-introducer method decision authored by the study lead 2026-10-24 08:46 IST. Adopted verbatim; extends the metric contract (METRICS.md) and BUG-CLASSIFICATION.md. Defines counting, not measured results. -->

# Bug outcome unit and multiple introducers

Decision: 2026-10-24 08:46 IST. This is a method decision, not an execution result.

Default primary unit: one behaviorally verified bug record per selected fix PR. Multiple blamed commits, fixed lines or introducing PRs do not create additional bugs or inflate HIT/MISS denominators. Split a fix into multiple bug records only if distinct faulty behaviors and separate FAIL-before/PASS-after witnesses are established and the split recorded before inspecting mutation outcomes. Keep an aggregate fix-PR count beside any bug-record count.

Mechanical blame identifies last-touch provenance, not by itself semantic bug introduction. For each verified behavior, use the witness and code history to identify the causally relevant mapped fixed-line subset and introducing change(s). Do not call every young blamed edit an independent bug or assume the largest blamed share is causal.

Execution order may put an easier or dominant-share introducing PR first, but that changes scheduling only. Freeze the intended component set and reason before replay results. Group multiple blamed commits in the same introducing PR into one replay of that PR, preserving the separate line maps. For HE #5692, the two currently listed commits both resolve to PR #5587 and therefore do not require two PR replays merely because there are two blame records.

A primary HIT/MISS is complete only when the verified bug's eligible, causally relevant mapped introducing components have their required replay evidence. HIT requires actual edited-span intersection on at least one such component. MISS requires all such components completed with no intersection. If an intersecting component is proven while others remain pending, report a component HIT witness and partial coverage, not a completed aggregate rate row. Skipped older/incompatible components are disclosed separately; if only a young compatible subset is evaluated, label the result as that subset rather than complete fix coverage.

Keep a separate descriptive introducing-component table with report IDs, line mappings and outcomes. Never mix its counts into the primary per-bug denominator. Deduplicate flag-rate lines per introducing PR across components; the same replay or line cannot count twice in a pooled flag denominator. If multiple bug records share an introducing PR, retain that cluster identity for intervals.

HE ledger v3 currently lists 20 signal-eligible candidates, 13 mechanically old-only cases and 7 pending-regression cases, with every denominator_included=false and every outcome=null. These are provisional selection/mapping statuses, not verified bug counts. The attached ledger does not contain the referenced per-candidate line-map files, raw blame/ancestry evidence, or FAIL/PASS receipts, so those mappings and age conclusions are not independently verified by this audit.
