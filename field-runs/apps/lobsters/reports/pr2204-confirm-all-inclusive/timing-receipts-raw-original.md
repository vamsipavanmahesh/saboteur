# Item 4 timing receipts: 2204 inclusive run - engine 490.26s vs ~48 min wall

## Wall anchors (filesystem mtimes, my live observations)
- 08:28:46  config/saboteur-inclusive.rb written (run launched ~08:29:30)
- 08:46:40  log shows map progress through "60 s elapsed, 175/861"
- 08:47:35  log shows map progress through "121 s elapsed, 350/861"
- 08:54:27  coverage-build.log last write ("425/861")
- 08:56:20  confirm log last write before mutant phase (map complete, "1 subject, 861 tests")
- 09:13:15-09:16:38  mutant-phase worker PIDs observed alive (neutral check), continuous
- 09:16:52  report JSON written (run end)
- Wall span config->report: ~48.1 min (2886 s)

## Engine-reported clock (report footer)
wall 490.26s = baseline 36.0s + map 252.5s + mutants 193.3s + ~8.5s overhead
Engine measures with CLOCK_MONOTONIC (saboteur-src/lib/saboteur/engine.rb:67,194,261: `monotonic` helper).
CLOCK_MONOTONIC on Linux does NOT count system suspend time.

## Observed stretches: engine clock vs wall clock
- 08:46:40 -> 08:47:35: engine 60s->121s (+61s) in ~55s wall. Ratio ~1:1 (box awake).
- 09:13:15 -> 09:16:38: entire mutant phase watched live, worker PIDs continuously
  active, ~203s wall; engine mutants = 193.3s, report written 09:16:52. Ratio ~1:1.
- 08:47:35 -> ~08:56:20: engine 121s->252.5s (+131s) over ~525s wall. Ratio ~4x dilated.
- ~08:56:20 -> ~09:13:30: ~17 min wall gap between map completion (last log write)
  and mutant-phase activity, engine clock advancing ~0s.

## Steal check
/proc/stat cpu steal column: 227 ticks cumulative (~2.3 s ever), unchanged across
samples. No host CPU steal.

## Conclusion
The 490.26s engine wall is monotonic executed time. The extra ~40 min of wall time is
periods where the sandbox VM was suspended (no CPU scheduled): the engine clock
correctly excludes them. Evidence: stage splits sum to the footer total; every stretch
I watched live runs 1:1 with the engine clock; dilation appears only in unobserved
gaps; zero steal. 2156 shows the same pattern (engine 344s vs ~30.5 min wall).
This is a sandbox-environment property, not a saboteur timing bug and not a test
stall. On an always-awake CI host, wall ~= engine time. Inference label: cannot
directly observe the freeze (observer is frozen too); mechanism is evidence-backed
inference from the receipts above, no alternative consistent with all four receipts.

## Cost note for CI
Baseline + coverage map = 288.5s of the 490.26s (~59%). With a cached/reused map in
CI, per-run cost approaches the mutants-only share (~193s for 16 subjects here).
