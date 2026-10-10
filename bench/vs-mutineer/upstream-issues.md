# mutineer issues found during the benchmark

Version: mutineer 1.6.0, macOS 14.3 (arm64), Ruby 3.4.3 and 4.0.0.
Each issue below is written to be filed as is. Paths are relative to the
target app. Nothing here has been filed; the maintainer decides.

## 1. `--daemon` rejects RSpec, and the README does not say so

What happens:

    RAILS_ENV=test bundle exec mutineer run app/models/tag.rb \
      --test spec/models/tag_spec.rb --rails --daemon --jobs 6
    mutineer: --daemon supports only --framework minitest (rspec is not implemented on the daemon path yet)

Expected: the README's "Faster, parallel-safe Rails (the `--daemon`
backend)" section and the `--daemon` row of the options table say it is
Minitest-only, so RSpec users know `--rails` will run on one worker.

Impact: on an RSpec Rails app, mutineer cannot use more than one worker
(`--rails` without `--daemon` forces `--jobs 1`).

Reproduction: any Rails app with RSpec (seen on lobsters at ede993e0).

## 2. Coverage capture crashes on macOS after a Rails boot (Objective-C fork safety)

What happens: with `--rails` on a Postgres app (human-essentials at
d6f8290), coverage capture forks the booted app and the children abort:

    objc[8333]: +[__NSCFConstantString initialize] may have been in progress in another thread when fork() was called. We cannot safely call it or ignore it in the fork() child process. Crashing instead.
    [mutineer] coverage skipped for spec/...: fork capture produced no result (re-run with --verbose for the error)
    mutineer: no test recorded coverage, and capture failed for spec/controllers/...

428 aborts in one run; the run then stops.

Workaround that worked: `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` and
`PGGSSENCMODE=disable` in the environment. (libpq's GSSAPI probe after fork is
a known crash source on macOS.)

Suggestion: document both under Rails, or set them for the children when
running on macOS.

## 3. The clean check names failing files a few at a time

What happens: on human-essentials, six spec files fail when run on their own
(they are green only inside the whole suite). mutineer's clean check found
them over three runs of about 13 minutes each: first five files, then a
"combined suite" failure, then the sixth file. Running each file alone with
plain RSpec found all six in one 18-minute pass.

Suggestion: run the per-file clean check over every covering file and
report the full list in one run, or offer a `--check-isolation` mode.

## 4. "fork capture produced no result" changes from run to run, and `--verbose` adds nothing

What happens: after the workarounds in issue 2 and the files in issue 3
were removed, two more runs on human-essentials each skipped coverage for a
different set of 4 to 5 spec files ("fork capture produced no result") and
then stopped with "the unmutated suite is not green (combined suite)". The
same 209 files pass with plain RSpec. A run with `--verbose` printed no
extra detail about either failure.

Expected: `--verbose` shows the child's error for a failed capture and
for the combined clean run.

Reproduction: human-essentials at d6f8290, sources app/models/item.rb,
209 spec files (bench/vs-mutineer/configs/human-essentials/tests.txt),
`--rails`, Postgres 16, macOS 14.3. Logs: raw/findings/he-mutineer-try*.log.

## Not filed (needs a repeat first)

- One run on hashie with `--jobs 1` took 2,640 s for 409 mutants, while the
  same mutants took 34.9 s with `--jobs 6`, and a small file with `--jobs 1`
  was normal. Reproduce before filing.
