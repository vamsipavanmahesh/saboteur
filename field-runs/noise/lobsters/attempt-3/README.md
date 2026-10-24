# Lobsters noise-15 selection ATTEMPT 3 - QUALIFIED (independent live verification 08:28 IST)

This is the lobsters noise metric selection. Supersedes attempt-1
(UNQUALIFIED, pin filter) and attempt-2 (INVALID, incomplete
enumeration); both preserved.

Independent live verification (raw: verification-20261024T0828IST.txt),
all PASS:
- raw page1: total_count 95, incomplete_results false, 95 items =
  exhaustive for merged>=2026-04-24; ledger 63 rows + 32
  unmatched-belowcutoff = 95/95;
- zero in-window (>= 2158 merged_at 2026-07-18T16:15:00Z) PRs
  missing from the ledger - the attempt-2 failure mode is closed;
- ORDER: live merged_at-DESC eligible-15 == producer order EXACTLY:
  2231, 2157, 2156, 2171, 2172, 2183, 2197, 2182, 2175, 2103,
  2205, 2174, 2204, 2178, 2158 (2157 01:32:33 > 2156 01:31:17 >
  2171 01:29:25 on 2026-09-14);
- merge SHAs spot-checked live for the three newly added rows
  (2157, 2156, 2158): all MATCH;
- all 15 are sqlite-era Ruby 4.0.0; NO MariaDB-blocked rows in this
  selection (2102/2073 correctly fall below the cutoff).

Audit error corrected: the 08:23 recomputation listed 2171 ahead of
2157/2156 - that was not a strict merged_at sort; the two runs
ordering is the correct one. The SET I computed matches.

Datum corrections (no selection impact; denominators use actual
diffs at replay time):
- 2182: live PR files = app/models/story.rb, app/models/user.rb,
  spec/helpers/users_helper_spec.rb -> app/lib count is 2, not 1;
  the ledger's "1 (story.rb only, other file is the spec)" is
  inaccurate. Eligibility unchanged.
- 2078 (below cutoff): API PR-files view shows 8 files, 3 app/lib
  (mod/tags_controller.rb, story.rb, user.rb); the ledger's 13
  comes from the first-parent..merge git diff. The two diff bases
  genuinely diverge for this merge; both numbers recorded with
  their bases.

EX-1 per-era qualification (producing run 08:27-08:28): targeted
user_administration spec at the 2204 and 2156 BASE trees ran GREEN
(5 examples, 0 failures), so the v2 EX-1 base maps excluded a GREEN
test and are NOT full-era-suite maps - they are superseded and
preserved with that label; EX-1 is valid only at the pin tree where
the spec is red. Corrective no-EX1 replays for 2204/2156 are
queued; 2231 whole-BASE no-EX1 boundary: 882 examples, 0 failures
(08:27:54). No published result may claim whole-era-suite coverage
from the v2 maps.
