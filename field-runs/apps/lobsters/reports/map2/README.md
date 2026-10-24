# Lobsters whole-suite map (map2, 2026-10-24 06:54 IST)

The map deliverable is COMPLETE; the whole-project mutation phase is
TRUNCATED and carries NO score.

## What was produced

- Coverage map BUILT and cached: map key
  b6e0e06cd380370b5ea5edebe76e559c2f870f2f68c82ce0e33738f8a9479ccc,
  749 subjects / 908 tests across 108 spec files, seed 1
  (../.saboteur/whole-suite-map-v2, coverage-<mapkey>.json,
  inputs-<mapkey>.json, preview.json).
- Three green full passes of the suite, each 908 examples / 0 failures:
  baseline check 1, baseline check 2, and the coverage map build pass
  (../.saboteur/baseline-1.log, baseline-2.log, coverage-build.log).
- EX-1 exclusion active: spec/features/user_administration_spec.rb was
  excluded via saboteur's rspec_args --exclude-pattern (user-approved
  06:52, banning-email test red on lobsters main 40753644 independent of
  saboteur). The excluded spec appears nowhere in the map or coverage
  artifacts; it is listed only as a hashed file input in
  inputs-<mapkey>.json, which records repo file hashes.

## What was NOT produced

- No mutation score. The whole-project mutation phase (11984 mutants,
  --jobs 1) was intentionally interrupted by field decision at 117/11984
  after the ETA grew from 194m23s to 251m52s, outside the 09:46 IST
  deadline. Exit code 130 = SIGINT field stop, not a saboteur verdict.
  The partial verdict symbols in logs/map2-20261024-0654.log are raw
  partial output, INVALID for any aggregate.
- No report.json exists for this run (the run stopped before writing
  one), so the pre-score fake-kill check has no JSON to run against for
  this packet; it runs on every report.json any later replay produces.

## Timing: UNRESOLVED, run window CONTENDED

measurement.json records started_at 2026-10-24T06:54:33.870067+05:30 and
ended_at 2026-10-24T07:14:47.142527+05:30, a span of 1213.272 s, while
its own wall_seconds field and the log footer record wall=502.41s. These
contradict; both are preserved raw and neither is presented as the
verified elapsed time. The "212 s" line in the log is a progress report
at 750/908 examples, not the final build duration. The run window
overlapped the serial PR bundle loop from 06:54:33 (contended). Peak RSS
501664 KiB (tool-measured). A clean uncontended rerun may happen only at
the end of the field window.

## Source pins

- saboteur 0.12.3 built from 6f87ccc98377bf0c23f3cf409006f0464c2aa67c
  (gem sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa)
- lobsters 407536444934ac7d78f4ce1c18f228e3891a8663

Derived companion file: measurement.derived-wallclock.json (added 07:23)
recomputes wall_seconds as ended_at - started_at = 1213.27s. The original
measurement.json (wall_seconds 502.41, monotonic) is immutable above.
Cause of the discrepancy remains OPEN (sandbox clock probe under replay
load showed 0.0s drift; not confirmed).
