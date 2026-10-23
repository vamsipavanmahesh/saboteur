# Getting started

The shortest path from install to a survivor you have dealt with. Commands
assume a Bundler project; outside one, `gem install saboteur` gives the same
executable, which you run as plain `saboteur run` without `bundle exec`. Ruby
3.3+ on Linux or macOS, RSpec only.

## 1. Install

```ruby
# Gemfile
gem "saboteur", group: :test
```

```sh
bundle install
```

Trying saboteur without touching your Gemfile, or on a Rails app, is covered
by the README's [30-second quick start](../../README.md#30-second-quick-start)
and [Rails apps](../../README.md#rails-apps) sections - the defaults
(`lib/**/*.rb` minus vendored `spec/`/`test/` shapes, `rails: false`,
`jobs: 1`) are for plain gems. Use SimpleCov?
Turn it off for the run: saboteur needs Ruby's `Coverage` for itself, and most
projects already guard SimpleCov with an environment variable.

## 2. Check the environment

```sh
bundle exec saboteur doctor
```

`doctor` reports Ruby, coverage, integration, Rails/SimpleCov and boot-file
checks, and writes nothing. Add `--suite` to also run the unchanged suite
(two passes by default) with your seed - the same check every real run starts with. See
[Check a project before mutation testing](doctor.md).

## 3. Run one method first

Do not start with the whole project. Pick one method you know well:

```sh
bundle exec saboteur run --subject 'Billing::Invoice#total'
```

This infers the specs by name (`billing/invoice.rb` runs
`billing/invoice_spec.rb` and its siblings). If your spec lives somewhere
else, the run stops with exit 2 before anything boots and names the ways
out: pass `--test spec/your_spec.rb`, or append `--all` to use the whole
suite for this one method.

A `--subject` pattern that matches no subject fails the run the same way
(exit 2): a typo must not pass as a green zero-subject run. When some
patterns match and others miss, the run keeps the matches and the summary
names the missing pattern and the matched count.

The run first executes the unchanged tests (two passes by default) - a kill
only counts when the same tests pass on the code without the change - then builds a per-test
coverage map (cached for later runs), then mutates. You get counts per
status, a score, and one numbered source block per surviving statement, with
the changed line as a -/+ pair. The JSON report lands in
`.saboteur/report.json`.

## 4. Read what it tells you

- **Score**: `(killed + timeout) / (killed + survived + timeout)`. Errors,
  resource-limit stops and no-coverage work sit outside it; [Scores](../scores.md)
  defines every number.
- **Survivor**: the exact change your tests did not notice, as a diff. Walk it
  from output to killing test with [How to read survivors](reading-survivors.md).
- **Rejected kill**: the "failing" test also failed on the unchanged code, so
  it is not evidence. These count as errors, not kills
  ([Rejected kills](../rejected-kills.md)).
- **Exit code**: 0 clean, 1 survivors, 2 usage or configuration, 3 tool
  failure, 4 time budget spent, 5 the unchanged suite failed its baseline
  check, 70 an internal crash. The contract is in the
  [stability policy](../stability.md).

## 5. Deal with each survivor

Two honest outcomes:

1. **Write the missing test.** Most survivors are a behavior nothing pins
   down.
2. **Accept it with a reason.** Some changes are equivalent - no test could
   notice them. Record those in `config/saboteur_ignore.rb`; an entry without
   a reason is rejected, and the ignore list changes the exit code, not the
   score.

Re-run the same command to watch the survivor count fall, or replay one
mutant by its digest ([Replay one mutant](replay.md)).

## 6. Put it in the pull-request loop

Once the first scope is clean, widen it to the changes on each branch:

```sh
bundle exec saboteur pr
```

The `pr` preset runs the lines changed since the default branch (`main`, or
whichever branch origin/HEAD points at; pass a ref to override) with one
baseline check and a ten-minute budget that does not fail the build on its own
(`saboteur audit` is the whole-project counterpart with JSON and HTML
reports). For CI, the [GitHub Action](../github-action.md) runs diff mode on
pull requests, advisory by default.

## Where to go next

- [FAQ](../faq.md) - databases, SimpleCov, exit codes, flaky suites.
- README "Usage" and "Configuration" - every flag and `config/saboteur.rb` key.
- [Best practices](../best-practices.md) - thresholds, cadence and review habits.
