# PR 2204 replay v2 - supported base whole-map restore (2026-10-24 07:43 IST)

The requested CI cache flow, observed end-to-end for the first time
this window: whole-suite map built on the BASE tree (8f1b5006), cache
restored via the supported pointer flow, then the PR replay rerun
against it. v1 (selected-spec scope, reports/pr2204-replay/) is kept
separate and unmodified.

Identity: saboteur 0.12.3 @ 6f87ccc98377bf0c23f3cf409006f0464c2aa67c,
Ruby 4.0.0, base 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76, head
ed722e449227b39ab6268f4260aaa66df95275bd, seed 1, jobs 1, EX-1
active (user-approved 06:52).

## Base map build (07:37:49 - 07:42:35)
- logs/pr2204-base-map-full-20261024-0737.log: 851 examples in 103
  spec files, baseline checks green, "747 subjects, 851 tests in
  coverage map"; mutation phase began (3/11576, eta ~213m) and the
  run was truncated exit 130 (SIGINT) - map build was the goal; the
  signal origin is not in the log (same boundary pattern as map3).
- measurement.base-map.json (raw): wall 285.6s, rss 500376, exit 130;
  envelope recomputes to 285.603s. status null / evidence_paths [].
- Artifacts: base-coverage.json, base-inputs.json,
  base-whole-suite-map-v2 (pointer), COMPATIBILITY-RECORD.md,
  RESTORE-RECEIPT.md (worker-written).

## v2 replay (07:43:34 - 07:44:07)
- Result: 19/22 killed, 3 survived, score 86.4%, exit 1 - IDENTICAL
  verdicts to v1. Publisher diff of v2 vs v1 report.json: same 22
  mutant IDs, ZERO status/killedBy differences; same 3 survivors
  (56ec2857eb8103bd comparison, 695982748e0e8ebb + 9786b8df27eddc21
  literal_number, all story.rb:777 Story#is_gone?).
- MEASURED exit=1 wall=33.72s rss_kb=393552; measurement.json matches;
  envelope recomputes to 33.725s.
- The restored whole-suite map was CONSUMED for survivor confirmation:
  "confirmation: 3 unconfirmed" + "the whole-suite coverage map covers
  none of the edited lines of 3 survivors, so they stay counted".
  Survivor block now lists covering tests that ran and passed
  (spec/models/story_spec.rb[1:27:2:1] + 18 more).
- Fake-kill: grep -c user_administration = 0 on every packet file;
  testFiles = spec/models/story_spec.rb (19 tests) only;
  rejectedKills = 0.

## Publisher independent verification
- Cache chain: base-inputs.json map_key =
  76ba0df91556eb663d67c4ea3d31f6e9f3c69508d00c3450c44595c3fbcdd431 =
  pointer file content (64-hex); map_digest =
  fca4fd4f0ca333ef6e0d5d1a11617419a8eaf6686255a1dfc5419d1dca668b22 =
  sha256(base-coverage.json). Pointer/artifact chain internally
  consistent.
- Prefix claims (receipt: Gemfile.lock + db/ identical base..head):
  corroborated via GitHub compare API on lobsters/lobsters
  8f1b5006...ed722e44 - 1 commit, ONLY app/models/story.rb (+1/-1)
  and spec/models/story_spec.rb (+50/-0) changed. Gemfile.lock and
  db/ untouched. config/saboteur.rb is untracked (setup file);
  identical-config claim is worker-attested (copied verbatim, EX-1
  rspec_args in both per COMPATIBILITY-RECORD.md).
- Source mechanism at pin 6f87ccc9: map_silent / warn_map_silent in
  lib/saboteur/engine/survivor_confirmation.rb (lines ~205-238) is
  exactly the observed warning; pointer contract whole-suite-map-v2
  in lib/saboteur/engine/coverage_store.rb (CACHE_INPUTS, pointer
  read as untrusted hint, 64-hex only).
- base-coverage.json mentions story.rb 16x but is_gone? 0x -
  consistent with the base map not covering the survivor's edited
  method lines. Receipt's compatibility claims are otherwise
  worker-written; no consume-time re-hash (trust marker) is a
  product-design fact, not something this packet proves safe.

## Scoped finding (product issue filed separately)
For THIS PR, the supported base-cache restore flow leaves all 3
survivors - all on story.rb:777, a line THIS PR edited - unconfirmed,
because the base-tree whole-suite map cannot cover lines the PR
changed. This is a scoped observation, NOT a universal claim about
all edited-line cases. No fix proposed.
