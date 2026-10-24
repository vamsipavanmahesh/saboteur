# Chatwoot noise-15 selection attempt 1 - QUALIFIED (merger live verification 08:25 IST)

Verified against live GitHub before adoption; raw transcript in
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
API merged_at population cross-check. The merger's live-API
verification above (window enumeration, file lists, skips - all
PASS) remains on record, but the selection is PROVISIONAL, not the
confirmed metric selection, until the lead's receipts clear it.
