# Replaying the Lobsters preparation

This packet preserves raw evidence from the original working directory. It has not been rerun from the published field-runs/ directory. commands.sh is a grouped replay recipe containing the recorded commands, not a literal shell transcript. The actual setup attempt chronology is in logs/bin-setup.log; failures are not hidden by the later successful provisioning.

From the saboteur repository root, place the included helpers at the historical paths before using commands.sh:

```sh
mkdir -p "$HOME/field-runs"
cp field-runs/apps/lobsters/env.sh "$HOME/field-runs/env.sh"
cp field-runs/apps/lobsters/runmeasured.py "$HOME/field-runs/runmeasured.py"
mkdir -p "$HOME/field-runs/saboteur-field-runs/apps/lobsters/logs"
mkdir -p "$HOME/field-runs/saboteur-field-runs/apps/lobsters/reports/baseline"
```

These output directories deliberately reproduce the historical EVIDENCE_DIR in env.sh. They do not create or require a separate GitHub repository. To collect new evidence directly into the existing saboteur repository, source env.sh and explicitly override EVIDENCE_DIR to the absolute field-runs/apps/lobsters path; record that command/path change with the new run. Do not overwrite the preserved original logs. commands.sh still records the historical absolute working paths.

Provisioning was performed without system installation rights. The Ruby binary package's text-script shebangs were changed, native headers were extracted locally, and the original libvips attempt was replaced after its recorded failure. This is not an unchanged app setup and is not a successful saboteur CI-flow test.

runmeasured.py uses time.time() subtraction for elapsed wall time. The recorded timestamps and raw timing value are preserved, but a monotonic clock was not used. Linux RUSAGE_CHILDREN.ru_maxrss is peak child-process RSS, not summed process-tree usage, database-service memory or whole-machine memory. stdout/stderr were captured separately by the execution environment, not by this helper.

Baseline exit status is preserved without subtraction or adjustment. Known pre-existing failures are named with their reasons in findings.md and the original RSpec JSON. No mutation run or whole-suite-map result is present yet. Rebuilding every historical PR's dependency environment is still unverified.
