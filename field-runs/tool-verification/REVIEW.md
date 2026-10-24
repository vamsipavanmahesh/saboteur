# Evidence-tool verification

Scope: report generator and optional measurement helper only. No application
execution, mutation score or Rails compatibility conclusion follows from these
checks. All fixtures are synthetic and confined to temporary directories.

Test runtime: Ruby 3.0.2p107, Python 3 on Linux x86_64.

Executed checks:

- `ruby -c script/summarize.rb`: Syntax OK.
- `ruby test/summarize_test.rb`: summarize fixture tests pass.
- `python3 test/independent_test.py`: 24 tests, OK.
- `python3 test/measure_test.py`: 4 tests, OK.
- Clean scaffold report generation, with and without `--select`: successful;
  no empty sample files created before PR evidence exists.

The fixtures follow the native schemaVersion 2 report shape, checked against
`lib/saboteur/reporter/stryker.rb` from the public saboteur repository at
64b5853a9c828d1412266074c1afdefab1b205c2. This checks format compatibility with
that source revision, not with the still-pending 0.13.0 release. Recheck the
released reporter if its schema changes.

Fixes after initial fixture probes:

- Compared file/location and semantic confirmation/kill-cause fields, rather
  than treating same-ID moved or reclassified mutants as identical.
- Rejected duplicate report IDs, ambiguous test IDs, duplicate CSV keys,
  unknown CSV classes and verification rows for absent/wrong-verdict mutants.
- Avoided freezing empty selections before any PR report exists, created
  missing output directories and hashed the entire candidate pool.
- Kept empty verification CSV results unknown.
- Made measurement output directories and represented failed process-spawn
  RSS as unknown instead of zero. Preserved nonzero exits and signal exits.

The native score object is copied without inferring a score formula. Repeated
IDs across different PR scenarios remain distinct. Local test IDs are resolved
to recorded names before comparisons. Both parallel and determinism comparisons
emit an actual diff file, including when empty. Sampling uses sorted candidates
and Ruby `shuffle(random: Random.new(20261023))`, with caps of 25 survivors and
10 kills and refusal to overwrite a changed selection.

Limitations: CSV evidence references are not read or judged by the generator;
source-backed, independent survivor/kill verification remains necessary. The
script does not prove complete PR coverage, successful environments, release
identity, duration budgets, per-worker database isolation or correct human
interpretation of classifications. Resource measurements are child-process
peak RSS on Linux, not summed simultaneous-worker or whole-machine memory.
REPORT.pdf generation and visual inspection are outside this code-only check.
