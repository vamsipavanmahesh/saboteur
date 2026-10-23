# Acceptance harness

The maintainer's seven expected-behavior scenarios, recorded the day they were
written down, and checked against the real CLI. The harness builds the gem
from source into an isolated gem home, runs it against fixture repositories,
and compares what it does against `expected.yml`.

## Run it

    rake acceptance

Each case prints `PASS` or `FAIL` with a one-line reason. The task exits
non-zero when any case fails. A failure is a report, not a to-do for the
pull request that found it: either the expected result records something the
product does not yet do, or the product regressed. The maintainer decides
which; the harness never edits its own expectations.

## Layout

- `expected.yml` — the maintainer's expected results, transcribed verbatim
  (prose) plus the structured checks the runner performs.
- `runner.rb` — builds and installs the gem from source, runs each case,
  compares, reports.
- `fixtures/` — the fixture repositories each scenario runs against
  (generated into temporary directories at run time).

## Rules

- Expected results are the maintainer's words. Agents and contributors do
  not change `acceptance/` to make a failing case pass; the pull-request
  guard (`.github/workflows/acceptance-guard.yml`) rejects any pull request
  touching `expected.yml`, rejects acceptance/ changes from agent task
  branches (p<N>-...), and `CODEOWNERS` routes the rest to the maintainer.
- A scenario that fails today stays red in the report until the maintainer
  changes either the product or the expectation.
