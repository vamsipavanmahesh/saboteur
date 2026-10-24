# PR 2157 map+replay attempt c1 (lobsters) - merger audit: QUALIFIED PARTIAL, survivors CONFIRMED-but-UNCLASSIFIED (2026-10-24 10:05 IST)

Producer packet (report.json + 4 logs). Verified from raws:

MAP (c1): runner headmap2.sh sha256=255d0ae9e5523370e8bc85d85b25af3a7ab3424bc04de8b02089ffa246f8888b, tree pr2157 at 8e46ece70245f834e4f43a5563cd9b90efc6e1d0, 865 examples/105 spec files, 738 subjects/865 tests in coverage map, MEASURED exit=130 wall=769.12s = deliberate boundary stop AFTER map build completed (mutation phase had begun: "1/11715"). Observer (own PGID/PID identity, sha 6690b470...): BOUNDARY_STOP_ARTIFACTS_FRESH_VERIFIED key=4969a381d449168f220f5e9ef5bdaf268a20e3d37116a8863c9946270b9730c6.

REPLAY (c1r): --since d9998c2555317db7b3cb9a159ef7878ff993ab78. Merger API verification (10:05 IST): PR 2157 merge = 8e46ece70245f834e4f43a5563cd9b90efc6e1d0, sole parent = d9998c2555317db7b3cb9a159ef7878ff993ab78 - the --since base is the exact merge parent, so the replay diff is exactly PR 2157's changes. 11 mutants on StoriesController#show: 5 killed (2 assertion, 3 crash - ActionView::Template::Error 1, RuntimeError 1, ArgumentError 1; operators body_nil, body_raise, argument_removal), 6 survived, 0 rejected kills, exit 1, MEASURED wall=55.48s (engine footer 53.9s: baseline 2.6 + map 13.2 + mutants 30.7). Score 45.5% (5/11).

POINTER BRIDGE CONSUMED (stdout evidence): survivor blocks show "covered by 49 specs, incl. ./spec/jobs/cache_page_job_spec.rb[1:1:6] (not run here)" - the whole-map covering list - plus "confirmed: ... ran on confirmation and still passed" and "confirmation: 6 confirmed". All 6 survivors are tool-CONFIRMED (whole-pointer bridge engaged). They are UNCLASSIFIED for the noise metric (equivalent vs false_survivor vs environment_noise); triage is routed to a fresh independent tester per main. Noise: 6 unclassified survivors, denominator undefined until classification - NOT 0, NOT N/A.

PROVENANCE GAPS (provenance NOT yet qualified; packet holds logs+report only):
1. coverage-4969a381....json, inputs-4969a381....json and the whole-suite-map-v2 pointer file itself are NOT in the packet (only the observer-log digest). Needed to qualify map provenance.
2. logs/pr2157-headmap-driver-c1.log is EMPTY (0 bytes) - no attempt_start epoch, bundle/schema/prefix receipts for the map era.
3. No POST-replay pointer-unchanged receipt on the replay (consumption is proven by stdout; integrity-after is not receipted).
4. No Gemfile.lock/prefix receipts for the 2157 era trees.

Environment notes (informational): tool reports Ruby 4.0.0 path (ruby/ruby-4.0.0) on this lane; Landlock ABI 2 < 3 - sandbox runs hazard-guard + canary only (restriction of truncate() unavailable). Neither affects the counts; both stay disclosed.

Counts: study qualified count unchanged 1/45 (2231 only) until kill-cause and survivor-triage proofs land.
