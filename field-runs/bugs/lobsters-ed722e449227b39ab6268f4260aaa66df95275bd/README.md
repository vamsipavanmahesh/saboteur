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
