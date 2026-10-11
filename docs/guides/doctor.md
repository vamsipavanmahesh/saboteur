# Check a project before mutation testing

```sh
bundle exec saboteur doctor --seed 42
bundle exec saboteur doctor --config config/saboteur.yml --seed 42
```

Doctor checks Ruby 3.3+ and fork support, suspended line coverage, configured
require/hook files, and the RSpec integration. It prints the Rails setting and
whether SimpleCov was loaded and its start suppressed by saboteur's normal boot.
It does not certify a Rails/database version; successful boot and tests are the
check. Unmatched include/exclude patterns are warnings, not failures.

After normal project boot it runs the full filtered RSpec suite in two fresh
supervised children from the same parent state. Each pass seeds Ruby random
numbers and sets RSpec random ordering to the run seed. Both must pass, execute
all loaded test IDs and finish in the same order. Empty suites, timeouts,
resource stops and child exits fail. Use the same seed when fixing failures.

The two runs sample stability. They do not prove the suite has no flakes,
compare assertion values or vary seeds. Suite filters still come from rspec_args.

Doctor does not change methods, write reports, modify ignore files or write
coverage/verdict caches. Temporary suite-output logs are removed after each
check. Normal target boot files, hooks and tests still run and may change their
own databases/files/services. Only use it on a suite safe to run twice.

The timeout is baseline_timeout (default 300 seconds) per pass. Normal memory
and process limits apply. Exit 0 means these checks passed, 2 means bad arguments
or config, and 3 means environment, boot or baseline failure. Errors name the
check and suggested fix. Run through the executable so line coverage is set up
before target boot; disable other coverage starters for this process.
