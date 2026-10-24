# PR 2156 replay v2 - supported base whole-map restore (2026-10-24 07:52 IST)

Second observation of the supported CI cache flow. Base map built on
9a773eac, restored via the whole-suite-map-v2 pointer, PR rerun
against it. v1 (selected-spec scope, reports/pr2156-replay/) kept
separate and unmodified. Identity: saboteur 0.12.3 @
6f87ccc98377bf0c23f3cf409006f0464c2aa67c, Ruby 4.0.0, base
9a773eac0b49fd86b16585ad503de9a51919c496, head
d9998c2555317db7b3cb9a159ef7878ff993ab78, seed 1, jobs 1, EX-1
active (user-approved 06:52).

## Base map build (log logs/pr2156-base-map-full-20261024-0747.log)
- 859 examples, baseline checks green (859/0 per receipt), "738
  subjects, 859 tests in coverage map"; truncated exit 130
  (MEASURED wall=292.88s rss_kb=502924) after map build - same
  boundary pattern as the 2204 base map and map3; signal origin not
  in the log. No wrapper measurement.json for the base map in this
  packet (receipt + log footer only).

## v2 replay (07:52:08 - 07:52:24)
- 6/7 killed, 1 survived, score 85.7%, exit 1 - IDENTICAL verdicts
  to v1 (publisher diff: same 7 mutant IDs, ZERO status/killedBy
  differences; survivor 84a2b3ca16355339 condition_true,
  settings_controller.rb:51).
- MEASURED exit=1 wall=15.97s rss_kb=375392; measurement.json
  matches; envelope recomputes to 15.972s.
- Restored map consumed: "confirmation: 1 unconfirmed" + "the
  whole-suite coverage map covers none of the edited lines of 1
  survivor, so they stay counted". Survivor block lists the covering
  test that ran and passed (settings_controller_spec.rb[1:1:1]).
- Structured fake-kill (publisher): testFiles =
  spec/controllers/settings_controller_spec.rb only; every killedBy
  reference resolves to a testFiles id; rejectedKills=0; zero
  "user_administration" occurrences in the whole packet (grep).

## Publisher independent verification
- Cache chain: base-inputs.json map_key = pointer content =
  37d91f0473e9e5337aefca138cf8fb1c4f38e2afef99231f6b2716a71917f493;
  map_digest = bf54a2f1265b90bd06ada3bada2f4541558f527cc6e79a800242a358fdacf9b8
  = sha256(base-coverage.json). Distinct inputs from the 2204 cache
  (files differ).
- Prefix claims: GitHub compare lobsters/lobsters 9a773eac...d9998c25
  = 1 commit, ONLY app/controllers/settings_controller.rb (+2/-2)
  and spec/controllers/settings_controller_spec.rb (added, +23/-0);
  Gemfile.lock and db/ untouched - receipt corroborated. Identical
  untracked config remains worker-attested.
- The survivor sits on settings_controller.rb:51, a line this PR
  edited (log marks it "changed line"). Same map_silent source path
  as #2204 (survivor_confirmation.rb at pin 6f87ccc9).

## Scoped finding
Second observed instance of the #1345 shape: supported base-cache
restore leaves the edited-line survivor unconfirmed. Observed for
these two PRs only; no universal claim. The other three replay rows
(pr2231, pr2090, pr2182) remain selected-spec scope, unchanged.
Independent HEAD classification and cause checks are NOT done yet.
