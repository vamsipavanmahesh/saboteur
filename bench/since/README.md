# Diff mode on a real branch history

This measures a small source workload, not a whole-project run or a Rails
application. Both modes mutate `lib/saboteur/reporter/terminal.rb` with the
same config and coverage suite (380 unit tests). Full means the full configured
file, not every source file in saboteur.

## History and environment

- Engine and tests: main `d2b7abb336eae53ec8cd5a71c111f9daef66218a`.
- Real change: `4cb62f0f67ccd30fb8ce6fc1d2c0aabbfddca939` (add `--seed`).
- Base: its parent `1b520657a7b0241592590dce31f77aa3c2247c7b`; the full base SHA is in measurements.json.
- The terminal reporter has no later edits through d2b7abb. Its diff against
  the base is the real seed-reporting change, not a manufactured benchmark edit.
- Ruby 3.3.9, Prism 1.9.0, RSpec 3.13.2, Linux x86_64, jobs 1, seed 1.
- Cold coverage map on every invocation (`cache: false`); no incremental
  verdict reuse. The OS file cache is not flushed. No memory claim is made.

A wider pilot including CLI/config self-mutation had timeouts and errors; it
was excluded before choosing this recorded workload. This selected-file
measurement must not be extrapolated to all source files or Rails workloads.

## Results

Five paired runs, ordered full/diff then diff/full, alternating. Wall time
includes process startup, coverage mapping, mutation execution and JSON output.
The harness uses a monotonic clock around each complete command.

| Mode | Mutants | Median wall seconds | Min-max seconds | Verdicts in every run |
|---|---:|---:|---:|---|
| Full configured file | 139 | 16.686 | 16.157-19.471 | 127 killed, 11 survived, 1 no coverage |
| Diff | 7 | 12.862 | 12.744-15.842 | 6 killed, 1 survived |

The median wall time falls by 22.9% for this workload; the mutant count falls
by 95.0%. Fixed coverage-suite work limits the time saving. Both modes exit 1
because they have survivors; these are completed runs, not tool failures.
Every diff mutant is present in the full report with the same digest and
verdict in all five pairs. Verdicts also match within each mode across runs.
The modes deliberately check different mutant sets, so their scores and
survivor counts are not interchangeable.

## Rerun

Use a fresh, full-history checkout at d2b7abb with these `bench/since` files
copied into it. Keep lib/ and spec/ unchanged. Install the same dependency
versions using [Gemfile.lock](Gemfile.lock); copy that file to the project root
before `bundle install`. It pins dependencies without changing the repository's
normal dependency policy. Ruby 3.3+ and Python 3 are needed.

```sh
bundle install
(cd bench/since && python3 -m unittest test_measure)
python3 bench/since/measure.py --base 1b52065 --pairs 5 --output /tmp/since-results
```

`measure.py` records exact commands, exit codes, counts, environment and
per-pair times. It retains the original JSON and console logs in the output
folder and refuses a missing or mismatched shared-mutant verdict. The checked-in
[measurements.json](measurements.json) contains the raw timings and commands.
[verdicts.json](verdicts.json) contains every file/digest/status tuple from all
ten original reports for independent parity checks (durations and duplicated
source text are omitted). [workload.yml](workload.yml) is the common config.

This satisfies a measured diff-mode example on real history, not Milestone 1's
mid-size Rails exit criterion. It is evidence for choosing a narrower review
scope, not proof of any engine speedup, memory reduction or test-quality gain.
