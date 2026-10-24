# Publisher index + verification: lobsters-ed722e44 (fix PR #2204)

STATUS: DECISION PENDING (skip-rule exception asked of the user
08:17 IST). This entry is NOT a HIT and NOT a MISS. No saboteur run
on the introducing change exists; no noise/flag/hit-rate numbers are
or may be derived from this packet. No MariaDB setup will be launched
unless the user approves the exception.

Publisher verification (all against live GitHub, 08:18 IST):
- Introducing commit b8cc0cef58b3cf0c1d03dc0809c874b2e701b0b3:
  author date 2026-06-19T17:40:29Z (= BUG.md's "12:40:29 -0500";
  committer date 17:40:49Z, 20s later), message "don't imply mod
  removed a story hidden by heavy flagging of banned user", parent
  7037494eb85003603ecd87fb00bde994e111f103 - all match BUG.md.
- commits/b8cc0cef/pulls API returned [] (empty) - "no associated
  PR" verified, not just worker-claimed.
- Introducing patch (API): single file app/models/story.rb, hunk
  @@ -759,7 +759,7 @@, -`is_deleted? || (user.is_banned? && score < 0)`
  +`... && is_moderated = false` - assignment, not comparison.
- Line mapping verified by raw file reads: buggy line content
  `is_deleted? || (user.is_banned? && score < 0 && is_moderated = false)`
  sits at story.rb:777 at fix base 8f1b5006 and at story.rb:762 at
  b8cc0cef; parent 7037494e has the pre-buggy line without the clause.
- June-era DB claim verified: .github/workflows/check.yml at
  b8cc0cef runs mariadb:10.11.11; db/schema.rb:66 at b8cc0cef has
  MySQL-only `unsigned: true` - "needs a different DB (MariaDB/
  trilogy) than the sqlite field stack" is source-verified.
- Date eligibility verified: 2026-06-19 is within 6 months of the
  2026-10-24 request (cutoff 2026-04-24).
- Regression raws: regression-before-fix.txt (5 examples, 1 failure,
  failing example = the new is_gone? heavy-flagging spec at
  spec/models/story_spec.rb:510, BEFORE_EXIT=1, 08:14:00) and
  regression-after-fix.txt (5 examples, 0 failures, AFTER_EXIT=0,
  08:14:06) are worker-executed raw logs, internally consistent with
  the recorded procedure (head spec on base tree vs head tree).
  Publisher did not re-execute (no ruby in this sandbox); marked
  worker-run raw evidence. This demonstrates FAIL-before/PASS-after
  AT THE FIX PR ONLY - no portability to the June introducing tree
  is claimed or proven (June trees bundled green per ENVIRONMENT.md,
  worker-reported; no run executed there).
- Fake-kill: zero "user_administration" occurrences in the packet
  (grep). Note: EX-1 applies to saboteur runs; none happened here.

Conflict recorded (ENVIRONMENT.md): user rule B2 says skip when the
introducing era needs a different DB (MariaDB here); the same user
message explicitly says start with 2204's bug. Exception decision
pending with the user via main (08:17 IST).

## Append 08:19 - raw completeness archive (raws/ + line-map.json)

New raws, all publisher-verified:
- line-map.json: machine line map; numstat (1 add + 1 del) retained
  SEPARATELY from semantic 1-modified-line, pending approved metric
  definitions. Spec sha256 claims re-verified against the files:
  head 223d902815dc...20b21de, base-committed
  d67896e0482a...b90030a - both match. Status field:
  decision_pending_db_exception.
- raws/blame-fixed-line.txt: blame of the fixed line (b8cc0cef5,
  Peter Bhat Harkins, 2026-06-19 12:40:29 -0500, line 777, exact
  buggy content) - consistent with the live-API verification above.
- raws/introducer-git-show.txt + raws/fix-hunk.diff: hunks match the
  live GitHub patch data (@@ -759,7 +759,7 @@ introducing;
  @@ -774,7 +774,7 @@ fix).
- raws/introducer-ci-check.yml: byte-identical to the live file at
  b8cc0cef (cmp). raws/introducer-pulls-api.json: [] (fetched
  08:18:48). raws/introducer-ruby-version.txt: 4.0.0.
- raws/sqlite-schema-failure.log: ACTUAL failure evidence for the
  skip-rule assessment - "bin/rails aborted! ArgumentError: Unknown
  key: :unsigned" at db/schema.rb:66 in the bug2204-intro-base tree
  under the sqlite stack. Note: the footer's "exit=0" is the capture
  wrapper's status, not the rails command's; the abort text is the
  evidence.
- Restoration proof (base-cache contamination check):
  raws/base-git-status-before-restore.txt shows the temporary head
  spec copy staged (M spec/models/story_spec.rb);
  raws/base-git-status-after-restore.txt (08:18:44) shows it
  reverted. Timeline verified from published measurements: the 2204
  base whole-suite map (cache 76ba0df9) was built 07:37:49-07:42:35,
  BEFORE the temporary head-spec copy (regression runs 08:14) and
  the restore (08:18:44) - the built cache predates the copy, and
  the restored tree no longer carries it, so no new base-cache
  computation can include the head spec. Remaining working-tree
  modifications (Gemfile/Gemfile.lock saboteur-gem environment
  additions, untracked config/saboteur.rb) are the pre-existing
  recorded environment state, not new contamination.

The 4 earlier files (BUG.md, ENVIRONMENT.md, regression-*.txt) are
byte-identical to this archive's copies (cmp) - left untouched.
Still DECISION PENDING; no HIT/MISS; no metrics until definitions
are approved.

## Append 08:21 - provenance corrections (main's audit)

- introducer-pulls-api.json is NOT valid JSON as received (response
  body + trailing fetch-timestamp line). Original preserved
  byte-exact; derived valid-JSON response + metadata split out as
  introducer-pulls-api.response-DERIVED.json /
  .meta-DERIVED.txt (labeled, provenance above).
- Certainty correction: the pulls API returning [] means NO
  ASSOCIATED PR was returned by the API. It is NOT proof of a
  "direct push to master" - no event evidence exists in this
  packet. The "direct push" phrasing in BUG.md and in
  line-map.json's pr_association is the worker's prose, preserved
  raw, and should be read as unproven characterization; a
  clarification lands with the user's exception decision.
- SQLite schema-failure log: the "exit=0" footer is the capture
  wrapper, not the rails command (kept qualified).
- Cache-contamination claim STRENGTHENED to content level (no rerun
  needed): the published 2204 base inputs snapshot
  (reports/pr2204-replay-v2/base-inputs.json, map_key 76ba0df9)
  pins spec/models/story_spec.rb at digest
  d67896e0482accb8abe2449652376e66cf0c9522b529bfe3e42896023b90030a =
  sha256 of the COMMITTED base spec (raws/story_spec-base-committed.rb),
  NOT the head spec (223d9028...). The base map's inputs are the
  committed base spec content - uncontaminated by the later
  temporary head-spec copy by content, not only by timeline.

Entry remains DECISION PENDING; no HIT/MISS.
