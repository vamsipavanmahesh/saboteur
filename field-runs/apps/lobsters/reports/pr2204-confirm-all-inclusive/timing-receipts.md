# PR 2204 inclusive run - timing evidence: engine 490.26s vs ~48 min wall; cause UNDETERMINED (2026-10-24)

## Measured facts
- Wall anchors (filesystem mtimes, live observation): run config written 08:28:46; map progress 175/861 at 08:46:40 and 350/861 at 08:47:35; coverage-build.log last write 08:54:27; map complete by 08:56:20; mutant-phase processes continuously observed 09:13:15-09:16:38; report written 09:16:52. Wall span config to report: ~2,886 s (~48.1 min).
- Engine-reported wall (report footer): 490.26 s = baseline 36.0 + map 252.5 + mutants 193.3 + ~8.5 other; measured with CLOCK_MONOTONIC, which excludes system suspend time by definition.
- Observed stretches: 08:46:40-08:47:35 engine +61 s over ~55 s wall (ratio ~1:1); mutant phase 09:13:15-09:16:38 ~203 s wall vs engine mutants 193.3 s (ratio ~1:1). 08:47:35-~08:56:20 engine +131 s over ~525 s wall (~4x dilated). ~08:56:20-~09:13:30: ~17 min wall gap with engine advancing ~0 s.
- Arithmetic: 2,886 s wall - 490.26 s engine = 2,395.74 s (~39.9 min) of wall time not executed on the engine clock, almost all inside the two unobserved/dilated gaps.
- /proc/stat steal: 2.3 s cumulative, unchanged across samples. Low steal does not discriminate between VM suspension and ordinary process descheduling; an observer on the same box cannot observe its own freeze.
- PR 2156's row shows the same pattern (engine 344 s vs ~30.5 min wall).

## Verdict
Cause UNDETERMINED. The discrepancy is a clock-domain mismatch (monotonic executed time vs external wall time) localized to unobserved gaps. Candidate explanations include sandbox VM suspension and host process descheduling; the receipts above do not prove either, and no other saboteur-side or test-side stall is evidenced. Earlier wording attributing the gap to VM suspension is corrected to undetermined; the facts above are unchanged.

## What this means for reported times
Per-run timing claims in this study use the engine's monotonic stage values with the external wall anchors beside them. Per-PR timing under the snapshot-reuse flow (D51 item 4) will be measured per PR and reported; no per-PR estimate is promised from this receipt.
