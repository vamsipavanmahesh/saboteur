# Item 4 timing receipts: 2204 inclusive run - engine 490.26s vs ~48 min wall
# v2 (corrected): clock-domain discrepancy reported from receipts; cause UNKNOWN.

## Wall anchors (filesystem mtimes, my live observations)
- 08:28:46  config/saboteur-inclusive.rb written (run launched ~08:29:30)
- 08:46:40  log shows map progress through "60 s elapsed, 175/861"
- 08:47:35  log shows map progress through "121 s elapsed, 350/861"
- 08:54:27  coverage-build.log last write ("425/861")
- 08:56:20  confirm log last write before mutant phase (map complete, "1 subject, 861 tests")
- 09:13:15-09:16:38  mutant-phase worker PIDs observed alive, continuous
- 09:16:52  report JSON written (run end)
- Wall span config->report: ~48.1 min (2886 s)

## Engine-reported clock (report footer)
wall 490.26s; splits: baseline 36.0s + map 252.5s + mutants 193.3s (+~8.5s overhead).
Code receipt: engine reads Process.clock_gettime(Process::CLOCK_MONOTONIC) for wall
and stage splits (saboteur-src/lib/saboteur/engine.rb:587, used at :67, :194, :261).

## Observed stretches: engine clock vs wall clock
- 08:46:40 -> 08:47:35: engine 60s->121s (+61s) in ~55s wall. Ratio ~1:1.
- 09:13:15 -> 09:16:38: mutant phase watched live, worker PIDs continuously active,
  ~203s wall; engine mutants = 193.3s, report written 09:16:52. Ratio ~1:1.
- 08:47:35 -> ~08:56:20: engine 121s->252.5s (+131s) over ~525s wall. Ratio ~4x.
- ~08:56:20 -> ~09:13:30: ~17 min wall gap between map completion (last log write)
  and observed mutant-phase activity; engine clock advanced ~0s across it.
- Caveat on anchors: log mtimes are buffered-output write times, so stage boundaries
  on the wall axis are approximate.

## Steal check
/proc/stat cpu steal column: 227 ticks cumulative (~2.3 s ever), unchanged across
samples taken during this analysis (not sampled during the run itself).

## 2156 comparison
Same shape: engine 344s vs ~30.5 min wall. Not analyzed further.

## What this establishes
- The engine footer is a CLOCK_MONOTONIC measurement; the ~48 min span is wall time
  between filesystem receipts. The two clock domains disagree by ~40 min.
- The disagreement is not constant: stretches observed live track 1:1 with the
  engine clock; the gap accumulates in stretches with no live observation.

## Cause: UNKNOWN
The receipts do not determine why the engine's monotonic clock advanced only ~490s
across ~2886s of wall time. VM/container suspension is one possibility; the
available receipts (monotonic/wall gap, low cumulative steal sampled after the run,
observed 1:1 intervals) neither prove suspension nor rule out other causes
(clocksource behavior under the sandbox, engine-side timing scope, scheduling
artifacts). No claim is made about saboteur correctness or about stalls either way.
Attributing the gap would require a direct platform signal, which is not available
here. No CI wall-time prediction is made from these numbers; the stage splits above
are engine-measured values only.
