# PR 2204 inclusive run - timing evidence: engine 490.26s vs ~48 min wall; cause UNKNOWN (2026-10-24)

Aligned to the verifier's corrected v2 (raw preserved as timing-receipts-raw-v2.md; the superseded v1 as timing-receipts-raw-original.md).

## Measured facts
- Wall anchors (filesystem mtimes, live observation): run config written 08:28:46 (launch ~08:29:30); map progress 175/861 at 08:46:40 and 350/861 at 08:47:35; coverage-build.log last write 08:54:27; map complete by 08:56:20; mutant-phase processes continuously observed 09:13:15-09:16:38; report written 09:16:52. Wall span config to report: ~2,886 s (~48.1 min). Caveat: log mtimes are buffered-output write times, so stage boundaries on the wall axis are approximate.
- Engine-reported footer: 490.26 s; stage splits baseline 36.0 + map 252.5 + mutants 193.3 = 481.8 s, remaining ~8.5 s overhead. Measured with CLOCK_MONOTONIC (engine.rb:587, used at :67/:194/:261), which excludes system suspend time by definition.
- Observed stretches: 08:46:40-08:47:35 engine +61 s over ~55 s wall (~1:1); mutant phase ~203 s wall vs engine 193.3 s (~1:1). 08:47:35-~08:56:20 engine +131 s over ~525 s wall (~4x). ~08:56:20-~09:13:30: ~17 min wall gap with the engine advancing ~0 s.
- Arithmetic: ~2,886 s wall - 490.26 s engine = ~2,395.7 s (~39.9 min) of wall time not executed on the engine clock, accumulating only in unobserved stretches.
- /proc/stat steal: 2.3 s cumulative, sampled after the run (not during); does not discriminate between suspension and other causes.
- PR 2156's row shows the same shape (engine 344 s vs ~30.5 min wall); not analyzed further.

## Verdict: cause UNKNOWN
The receipts do not determine why the monotonic clock advanced ~490 s across ~2,886 s of wall time. VM/container suspension is one possibility; the receipts neither prove it nor rule out others (clocksource behavior, engine timing scope, scheduling artifacts). No claim is made about saboteur correctness or stalls either way. The v1 wording (VM-suspension attribution, "no alternative fits", CI wall-time forecasts) is retracted; stage splits are engine-measured values only. Per-PR timing under the snapshot-reuse flow (D51 item 4) will be measured per PR and reported; no estimate is promised from this receipt.
