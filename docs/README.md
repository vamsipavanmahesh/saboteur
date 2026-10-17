# saboteur documentation

## Start here

- [Getting started](guides/getting-started.md) - install to a clean first scope.
- [Your first 10 minutes on a Rails app](guides/first-10-minutes-rails.md) - a narrated real run: install to a killed survivor.
- [FAQ](faq.md) - requirements, databases, SimpleCov, exit codes, flaky suites.
- [Project site](index.html) - pitch and benchmark numbers; the quickstart sits on its own page there.
- [Comparison with other tools](compare.html) - saboteur, mutineer and the wider open-source mutation testing landscape.
- [Best practices](best-practices.md) - thresholds, cadence and review habits.

## Guides

- [Check a project before mutation testing](guides/doctor.md) - `saboteur doctor`.
- [Saboteur vs flaky tests](guides/flaky-tests.md) - baseline refusals, real output, fixes.
- [How to read survivors](guides/reading-survivors.md) - from output to the killing test.
- [Replay one mutant](guides/replay.md) - re-run a single mutant by its digest.
- [Monorepos, sub-gems and the custom map](guides/monorepo-and-custom-map.md) - include scope, spec paths, real refusals.
- [Reading a survivor report and fixing survivors](guides/reading-and-fixing-survivors.md) - a real batch from report to clean exit.
- [saboteur in CI on large Rails apps](guides/ci-large-rails.md) - diff mode on PRs, sharded scheduled audits, caching.

## Using saboteur

- [Mutation testing on pull requests](pull-requests.md) - the diff-mode workflow.
- [Saboteur in CI on a pull request](guides/ci-pull-request.md) - a narrated real PR check on a Rails app.
- [GitHub Action](github-action.md) - advisory-by-default PR checks, baseline gate.
- [Scores](scores.md) - what every number on the report counts.
- [Stability policy](stability.md) - the agent JSON, exit codes and report contracts.
- [Baseline stability check](baseline-stability.md) - the unchanged-suite runs before mutants start.
- [Rejected kills](rejected-kills.md) - why a kill can turn into an error.
- [Survivor ranking](survivor-ranking.md) - the review order of findings.
- [Recipes](recipes/README.md) - hooks for common test tools.
- [Real-run feedback](real-run-feedback.md) - the template for reporting a run.

## Operators

- [argument_removal](operators/argument_removal.md)
- [arithmetic](operators/arithmetic.md)
- [body_false](operators/body_false.md)
- [body_nil](operators/body_nil.md)
- [body_raise](operators/body_raise.md)
- [body_true](operators/body_true.md)
- [boolean_logic](operators/boolean_logic.md)
- [chain_removal](operators/chain_removal.md)
- [comparison](operators/comparison.md)
- [condition_false](operators/condition_false.md)
- [condition_negation](operators/condition_negation.md)
- [condition_true](operators/condition_true.md)
- [element_removal](operators/element_removal.md)
- [endpoint_replacement](operators/endpoint_replacement.md)
- [filter_replacement](operators/filter_replacement.md)
- [interpolation_removal](operators/interpolation_removal.md)
- [literal_boolean](operators/literal_boolean.md)
- [literal_number](operators/literal_number.md)
- [literal_string](operators/literal_string.md)
- [method_swap](operators/method_swap.md)
- [negation_removal](operators/negation_removal.md)
- [operand_replacement](operators/operand_replacement.md)
- [operator_assignment](operators/operator_assignment.md)
- [or_assign](operators/or_assign.md)
- [pair_removal](operators/pair_removal.md)
- [range](operators/range.md)
- [regex_replacement](operators/regex_replacement.md)
- [safe_navigation](operators/safe_navigation.md)
- [statement_removal](operators/statement_removal.md)

## Decisions and background

- [Literal operator expansion](literal-operators.md), [filter polarity](filter-operators.md),
  [positional argument removal](argument-removal.md), [hash and keyword pair removal](pair-removal.md) -
  the design notes behind those operator families.
- [Minitest](minitest.md) - why saboteur is RSpec-only, and what an adapter would take.
- [Design](design.md) - how the engine works.
- [Prior art](prior-art.md) - the public research the design builds on.
- [Project status](status.md) - release, issues and roadmap pointers.

## Validation and benchmarks

- [Validation](validation/) - phase reports on real apps.
- [Benchmarks](benchmark/) - the current numbers and the archived comparisons.
- [Research survey](research/survey.md) - related-work reading.
- [Independent reviews](review/) - the archived reviewer rounds.

## For contributors and agents

- [Preflight](preflight.md) - the local check before review.
- [Exact-head panel gate](panel-head-gate.md) - how pull requests are gated.
- [Saboteur for AI coding agents](agent-skill.md) - the `saboteur agent-skill` block.
- [Declared run-input fingerprint contract](run-fingerprint.md) - the fingerprint building block.
