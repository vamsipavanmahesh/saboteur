# PR 2231 replay v2 (2026-10-24) - QUALIFIED RAW with a material qualification

Identity verified: head 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8,
base 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c (identity-proof.txt;
merger API audit 15/15 + ancestry behind_by=0). Fake-kill gate: 0
user_administration occurrences in report.json; rejectedKills=0.

MATERIAL QUALIFICATION - restored whole-suite base map NOT consumed:
the replay log records "coverage cache miss: settings, Ruby or
saboteur version changed", then builds its own map over 44 tests
(3 inferred spec files). So this replay ran on a 44-test
inferred-spec map, NOT on the restored 741-subject whole-suite base
map (coverage-map.json, from the exit-70 base run - that run's
outcome is EXIT 70, cache qualified-after-crash-path, see
base-map-exit70-context.txt and issue #1347). This row therefore
CANNOT be claimed as a whole-suite-map replay; it is a second
selected-spec replay. The restore flow failing to take effect for
this PR is itself a recorded finding.

Result (tool verdicts, worker-run): 4 mutants, 4 killed, 0
survivors, findings.order [] -> top finding N/A; score 100.0%;
exit=0, wall=32.8s, rss=377856KB; seed 1; --since 372345a2; jobs=1.
killedBy: de581860+a40b6c22 -> spec 0 (email_reply_mailer_spec[1:1]),
5ea32ddf+46132a21 -> spec 7 (comment_spec[1:10:3]); coveredBy
14/14/12/12 tests. Cause classes (worker's "crash share 1,
assertion 0" structure) are tool labels pending independent cause
proof per D12 - not verified here. Mutated span: app/models/
comment.rb lines 466-475.

Ledger corrections (ledger-v3-corrections.md) accepted and already
reflected at noise/lobsters/attempt-3/: 2182 count 2 (git/API
diff-base divergence unresolved, replay operates on the git
first-parent diff), 2078 below-cutoff divergence recorded.
SELECTION-RULE-v3.md, noise-ledger-v3.csv, pr2231-base-map log and
basemapwatch log in the received packet are byte-identical to
already-published files and are referenced, not duplicated.

## Amendment 08:42 IST - PROVISIONAL status + extraction correction + miss diagnosis

- The 4 kills / 0 survivors are PROVISIONAL: they do not qualify the
  expanded-noise 2231 row, because the restored whole-suite base map
  (741 subjects / 882 tests) was created but NOT consumed. Any
  future cache-miss row is rejected as a full-BASE-protocol row; no
  selected-spec fallback counts.
- Correction of a derived extraction: identity-proof.txt claims
  "report.json: mutants=0 killed=" - wrong extraction; the actual
  report.json files[].mutants has 4 mutants (all Killed, killedBy
  specs 0/0/7/7). Original file preserved; this note is the
  correction.
- Cache-miss mechanism (merger's read of pinned source 6f87ccc9):
  the cache key binds key_files (mutation-scope + integration
  test_files + suite files + lockfiles) and a settings digest over
  CACHE_INPUTS = integration, require, rspec_args, rails, tests,
  coverage_recorder (coverage_store.rb:18,164-168); the miss note's
  "settings, Ruby or saboteur version changed" class means the
  stored snapshot's settings or runtime digest differed
  (coverage_miss_note.rb:81-84), i.e. one of those six config
  values (or the Ruby/gem identity) differed between the base-map
  run and the replay. WHICH key differed is not derivable from the
  published raws; the worker must produce the replay-side miss note
  detail, reconcile settings (no flag drift between map build and
  replay), and rerun. The 2204/2156 restores hitting while 2231
  misses is consistent with a settings/config difference, not a
  file-digest one.
