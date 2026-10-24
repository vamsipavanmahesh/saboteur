<!-- Provenance: frozen six-month cutoff clarification authored by the study lead 2026-10-24 08:50 IST, grounded in the user's original 08:11:34 IST request. Adopted verbatim; confirms METRICS.md 08:22 and DECISIONS.md D33. -->
<!-- Publication note (merger, 08:50 IST): the author's closing "v3 packet lacks line-map files / ledger-consistency check only" caveat reflects the author's local packet at writing time. The merger's subsequent full audit (DECISIONS.md D33, noise/human-essentials/BUG-LEDGER-V3-CUTOFF-INVARIANCE.md) recomputed all 1,224 blame entries from the actual line-map raws: the 13-old/7-pending split is exact, and zero records fall in the 8h11m34s boundary margin, so the exact-time alternative recomputes identically. Temporal classification is closed; the semantic-causality caveats (unmapped additions, doc/spec provenance) remain open and are carried in the invariance proof. -->

# Frozen six-month eligibility cutoff

Decision clarification: 2026-10-24 08:50 IST. This preserves the study-relative anchor recorded in METRICS.md and DECISIONS.md at 08:22. It does not move the window to favor measured outcomes.

## Source and interpretation

Original user request received Saturday, October 24, 2026 at 08:11:34 IST: B1 asks for merged bug-fix PRs "from the last 6 months"; B2 asks to find the introducing commit/PR and "Skip if it's older than 6 months or needs a different DB or Ruby; record the skip."

The text does not explicitly name B2's reference timestamp. Chosen shared interpretation, documented at 08:22: both B1 and B2 use the original study-request calendar window, not six months before each fix PR. Fix-relative age is a different definition and must not silently replace the frozen one.

## Exact bounds and arithmetic

- Request anchor: 2026-10-24T08:11:34+05:30 = 2026-10-24T02:41:34Z, Saturday.
- Six calendar months earlier: April 24, 2026, Friday. This is a calendar-month subtraction, not a fixed 180-day duration.
- Preserve the already-used inclusive calendar-date convention: lower bound 2026-04-24T00:00:00+05:30 = 2026-04-23T18:30:00Z.
- Candidate PRs: merged_at >= lower bound AND merged_at <= each app's recorded frozen collection cutoff. Do not include PRs merged after that cutoff merely because enumeration runs later.
- Introducer age: committed timestamp >= the same lower bound. Earlier is old. Store committed and authored times separately; compare instants after timezone normalization. An introducing commit must precede the relevant fix and have source-grounded mapping/ancestry, not merely pass this age check.
- The exact-time alternative would start at 2026-04-24T08:11:34+05:30. Do not switch to it mid-study. Any records within the boundary's 8h11m34s margin must be listed so the alternative is recomputable.
- Do not use fix.merged_at minus six months. Preserve any results produced with that alternative as superseded derivations, then recompute eligibility from raw timestamps using this contract.

The April 24 lower bound remains fixed even while execution continues later in the day. A later data-collection extension requires its own timestamped decision and a new selection version; it does not automatically age earlier candidates out.

## HE v3 packet check and limits

The supplied ledger's stored introducing_age timestamps, normalized to UTC, provisionally divide into seven candidates with at least one April-24-or-later last-touch commit and thirteen with none. This arithmetic agrees with its 7/13 descriptive grouping, but does not validate the line population, original blame evidence, semantic causal introduction or complete handling of unmapped additions. The v3 packet lacks the referenced line-map files, so this is a ledger-consistency check only. A merger's separate fix-relative computation may be wrong even when these broad counts happen to agree.

Unknown/unmapped age is unresolved, never automatically old. Added-only unmapped ranges, documentation/spec provenance and mixed-age source changes require the separate mapping and semantic-witness checks. No HIT/MISS denominator is established by this cutoff document.
