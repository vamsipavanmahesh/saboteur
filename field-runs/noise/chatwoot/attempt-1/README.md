# Chatwoot noise-15 selection attempt 1 - QUALIFIED (independent live verification 08:25 IST)

Verified against live GitHub before adoption; raw log in
verification-20261024T0825IST.txt:
- develop HEAD at collection: 98a9ed710ad7334b07e96ca6c1da0b7e8ebc686a
  matches live branches/develop exactly;
- cutoff frozen 2026-10-24T08:23:20+05:30 (cutoff.txt);
- full window enumeration (33 merged PRs base:develop at/after the
  oldest selected PR's merged_at): ZERO PRs missing from the ledger;
- all 15 selected PRs' app//lib Ruby file lists match live
  /pulls/N/files exactly;
- all 25 skips verified: each has 0 app//lib Ruby files live;
- rule has no old-pin ancestry filter (corrected study rule).

Selected 15 and skips: see noise-selection.json (76 candidates
examined, 35 eligible). This is the metric selection for the
chatwoot noise stage. Replay trees are recent develop commits, not
the 0.13.0-era pin; per-tree checks apply. Environment deviations
(source-built toolchain, CE scope strip, path-gem pin
6f87ccc98377bf0c23f3cf409006f0464c2aa67c, fiddle addition,
landlock ABI 2 limitation, serial default) are in
../PRODUCER-DECISIONS.md and must ride with every chatwoot packet.
Fake-kill check: no score files in this packet; prose mentions of
excluded specs are not score evidence.

## Status change 08:26 IST - QUALIFIED -> PROVISIONAL

Study-lead ruling 08:26: no 15-PR population stays qualified until
the lead's own audit receipts pass; the git-log-#N freeze method is
under author audit and the execution queue is halted pending a live
API merged_at population cross-check. The independent live-API
verification above (window enumeration, file lists, skips - all
PASS) remains on record, but the selection is PROVISIONAL, not the
confirmed metric selection, until the lead's receipts clear it.

## Status change 08:26 IST (second) - PROVISIONAL -> QUALIFIED on reconciliation

Independent reconciliation against live API (raw:
reconciliation-20261024T0826IST.txt):
- ORDER: live merged_at-DESC eligible-15 == packet selected order,
  exact: 16092, 15761, 16094, 16358, 16208, 16093, 16266, 16329,
  16281, 16328, 15594, 16185, 16182, 16319, 16317. Set match too.
- Boundaries reconciled: selection window = 33 rows (merged_at >=
  oldest selected 2026-10-19T14:34:16Z) = 15 selected + 18
  in-window skips, all 18 present in the packet. The packet's 25
  skips = those 18 + 7 below-window zero-ruby rows (16071, 16234,
  16269, 16301, 16272, 16276, 16123). Producer's "76 examined,
  35 eligible" reconciles as 33 in-window + 43 below-window
  examined, 15 selected + 20 eligible-below-cutoff (16183, 16312,
  15807, 16297, 16299, 16292, 16279, 16230, 15978, 16253, 16254,
  16228, 16007, 16078, 16126, 15603, 16162, 15988, 16148, 16154 -
  all 20 confirmed eligible live). The 16 previously unaccounted
  rows are below-window zero-ruby merges the producer did not
  itemize; they cannot affect the top-15 selection.
- Conclusion: the selected 15 are the true latest-15 eligible by
  merged_at DESC at the frozen cutoff. QUALIFIED. The wider
  bug-candidate ledger remains a separate, incomplete stage and
  does not block this noise selection.
