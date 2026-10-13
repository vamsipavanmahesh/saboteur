# Minitest

Saboteur supports RSpec only. A Minitest suite cannot be run with it today, and
there is no supported way to point it at another test command: `--test-command`
(#140) is not built, and it is planned as a fallback for apps on Ruby older than
3.3, not as a Minitest path. This page records how much of the engine depends on
RSpec, so the decision to add a Minitest adapter, or to keep the stance, is made
on measured facts.

## How much of the engine is RSpec-specific

Measured on main at 6f704c8 with `git ls-files lib` and `grep`, not with a
prototype adapter.

- `lib/` is 10,313 lines of Ruby. The RSpec adapter (`integration/rspec.rb`)
  and its focus guard (`integration/focus_guard.rb`) are 311 lines, 3 %. They
  are the only files that call into RSpec to load, select and run examples.
- The adapter contract is small: `Integration::Base` has `setup`, `all_tests`,
  `run(ids)`, `run_all(recorder)`, `run_baseline(seed:)` and `test_files`, and a
  `RunResult` with the passed flag, failed ids, executed ids, runtime, failure
  classes and messages. Coverage mapping, test selection, the scheduler,
  forking, timeouts and the mutation operators are mostly framework-neutral
  and work from that contract. The exceptions are listed in the table below:
  the kill classification, the baseline check, test-id parsing in the
  reporters and the result cache, and the cache key.

Outside the adapter, RSpec shows up in these places. A Minitest adapter would
have to deal with each one:

| Where | What it assumes |
| --- | --- |
| `execution/runner.rb` | Assertion kills are told from crash kills by three RSpec class names. A `Minitest::Assertion` would count as a crash, so the assertion share would read 0 %. |
| `baseline_health.rb` | Failure detail and the run order read `::RSpec.world` and `::RSpec.configuration` when RSpec is loaded. |
| `doctor.rb` | `saboteur doctor` refuses any integration but `rspec`. |
| `reporter/stryker.rb`, `engine/result_cache.rb` | Test ids look like `./spec/a_spec.rb[1:2]`; the file is cut out of the id. |
| `engine/suite_files.rb`, `engine/run_fingerprint.rb` | The cache key reads `.rspec`, `.rspec-local` and `rspec_args`. |
| `engine/boot.rb` | `spec/` is put on the load path the way `rspec` does. |
| `config.rb`, `cli.rb`, `engine.rb`, `engine/coverage_store.rb` | `integration` defaults to `rspec`; `rspec_args` is a config key and a cache input. |
| Help, README, agent skill, install generator | The text says RSpec. |

None of these is a design obstacle. Together they are the real size of the
job, and they are larger than the adapter file.

## What a one-process probe showed (unverified)

This is an author-reported probe, not a measurement in the repository. A
30-line throwaway script (not committed) used Minitest 6.0.6 to check the part
the engine needs most: load once in the parent, run chosen tests in a forked
child. The results below are unverified until someone reruns a probe like it.

- `require "minitest"` and requiring the test file does not autorun anything.
- `Minitest::Runnable.runnables` and `runnable_methods` list `Class#test_name`
  ids after `Minitest.seed` is set.
- In a forked child, `Minitest::Runnable.run(klass, method_name, reporter)`
  runs one chosen test, and a reporter's `prerecord` and `record` see the
  start and the result. That is the hook the coverage recorder needs. Stopping
  after the first failure is a plain loop.
- A failed `assert_equal` reports as `Minitest::Assertion`. `nil.foo` reports
  as `Minitest::UnexpectedError`, not `NoMethodError`: Minitest 6 wraps an
  exception raised inside a test in `UnexpectedError`, which is a subclass of
  `Assertion` ([minitest.rb at v6.0.6](https://github.com/minitest/minitest/blob/v6.0.6/lib/minitest.rb)).
  An adapter has to check for `UnexpectedError` first and read its `error` to
  get the real class. Testing for `Assertion` alone would count every crash as
  an assertion kill.

Not checked: Rails `ActiveSupport::TestCase` (transactional tests, fixtures),
`parallelize_with`, `Minitest::Spec`, `minitest/hooks` suite-level hooks, a
per-test coverage run, and older Minitest versions (the API differs between 5
and 6). Any estimate of effort for those is a guess.

## Decision

Keep Minitest unsupported for now. The adapter is not the hard part. Each of
the places above needs a small, correct change and its own tests, and the
Rails case needs proof on a real app before anyone promises it. If a Minitest
adapter is wanted, build it as its own change, starting with the assertion
class and id format, and measure it on one Minitest gem and one Rails app first.

Until then there is no Minitest path in saboteur.
