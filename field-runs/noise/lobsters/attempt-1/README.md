# Lobsters noise-15 selection ATTEMPT 1 - UNQUALIFIED, SUPERSEDED PENDING

This selection is NOT confirmed and MUST NOT be used as a metric
input. It is preserved raw because the skip ledger must stay
auditable. A fixed collection (live PR merged_at-desc, last 15
eligible per the user's actual rule) is being produced after the review
halted the run queue at 08:17 IST.

Why unqualified (review ruling 08:20):
- The applied rule adds "merge commit is an ancestor of pin
  40753644" - a convenience restriction for the existing field
  stack that the user's rule does NOT contain ("the last 15 merged
  PRs per app touching app/ or lib/ Ruby, chosen by rule"). No
  convenience-filter replacement is authorized.
- The 2202 skip reason ("not ancestor of old pin") is therefore not
  a valid skip under the user rule. (Its second recorded reason, 0
  app/lib Ruby files, would independently exclude it under the user
  rule; not adjudicated here - the fixed collection decides.)

Publisher spot-verification of the raw data (live GitHub, 08:21):
- PR 2202: merged_at 2026-10-04T23:45:58Z, merge_commit_sha
  9fefd21bee25e4b4fddcfc318023b2d8cd7d8a5e - matches the ledger.
- compare 9fefd21b...40753644 = diverged (ahead 34, behind 1): the
  merge commit is genuinely NOT an ancestor of the pin - the
  ledger's ancestor=NO datum is accurate; the disqualification of
  the SELECTION is about the rule, not this datum.
- Fake-kill: zero "user_administration" occurrences in both files.

Load-bearing qualification for any historic/base replay rows (review
08:20): EX-1 (exclude spec/features/user_administration_spec.rb)
was approved for the pin tree's red state; that approval is not
proof the excluded test is red in every historical tree. The
the producing run will run a targeted spec check per actual tree before
applying EX-1 there, so green coverage is not silently excluded.
The fresh verifier is being notified to confirm EX-1 historical
test state.

Contents: SELECTION-RULE.md (producing run), noise-ledger.csv (44-row
candidate ledger with skips), this index. No replacements or new PR
options are invented by the publisher.
