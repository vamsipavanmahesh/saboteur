# Check a project before mutation testing

```sh
bundle exec saboteur doctor
bundle exec saboteur doctor --suite --seed 42
bundle exec saboteur doctor --test spec/models --seed 42
bundle exec saboteur doctor --config config/saboteur.rb --suite
```

By default doctor makes the environment checks only, so it finishes in seconds
even on a large suite. `--suite` also runs the unchanged suite twice, and
`--test PATH` (repeatable) runs only those specs twice; `--test` implies `--suite`.

Doctor checks Ruby 3.3+ and fork support, suspended line coverage, configured
require/hook files, and the RSpec integration. It prints the Rails setting and
whether SimpleCov was loaded and its start suppressed by saboteur's normal boot.
It does not certify a Rails/database version; successful boot and tests are the
check. Unmatched include/exclude patterns are warnings, not failures.

Ignore subjects are checked against every included source definition, not a diff
or test subset. Unmatched names warn with the exact instance/singleton naming
forms. A source parse failure makes that check incomplete rather than labelling
entries unmatched. This checks subject names, not mutation digests, and never
changes the ignore file. A malformed ignore declaration fails with a config
error before target boot, just as it does for a mutation run.

With `--suite` or `--test`, after normal project boot it runs the filtered RSpec suite in two fresh
supervised children from the same parent state. Each pass seeds Ruby random
numbers and sets RSpec random ordering to the run seed. Both must pass, execute
all loaded test IDs and finish in the same order. Empty suites, timeouts,
resource stops and child exits fail. Use the same seed when fixing failures.

The two runs sample stability. They do not prove the suite has no flakes,
compare assertion values or vary seeds. Suite filters still come from rspec_args.

Doctor does not change methods, write reports, modify ignore files or write
coverage/verdict caches. Temporary suite-output logs are removed after each
check. Failures include up to five failing example IDs and first-line messages.
Mutation-specific before_fork and around_mutant hooks do not run for baselines;
process-wide after_fork hooks still run in each child. Normal target boot files, hooks and tests still run and may change their
own databases/files/services. Only use it on a suite safe to run twice.

The timeout is baseline_timeout (default 300 seconds) per pass. Normal memory
and process limits apply. Exit 0 means these checks passed, 2 means bad arguments
or config, and 3 means environment, boot or baseline failure. Errors name the
check and suggested fix. Run through the executable so line coverage is set up
before target boot; disable other coverage starters for this process.
