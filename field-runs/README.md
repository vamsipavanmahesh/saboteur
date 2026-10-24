# Saboteur Rails field runs

Status: partial outcome at the four-hour stop. Application preparation and baseline evidence were collected. No saboteur 0.13.0 execution evidence was collected; this is not a completed Rails field test.

Commissioned by Vamsi Gunturu. Preparation and execution are performed by Instinct, an automated assistant. Independent triage is assigned separately after raw evidence exists. No human test execution or review is claimed.

The goal is to test whether saboteur can serve as a PR gate on three pinned public Rails/RSpec codebases. This field-runs/ evidence directory contains no Glomo code, private project code, credentials or internal operational records. It lives inside the saboteur repository; field testing does not change saboteur product code.

## Reproduce the report

From the saboteur repository root:

```sh
cd field-runs
ruby script/summarize.rb
ruby script/summarize.rb --select
```

The first command generates REPORT.md from app metadata, raw reports, measurement records and verification CSVs, plus findings.md. The second records the deterministic samples for independent verification. Once verification starts, do not replace sample files without documenting why. Do not treat missing evidence as zero.

The saboteur version and source SHA used in each actual run must be recorded in its measurement.json. Until a verified release is available, these remain unknown. App preparation is not evidence for a released saboteur version.

## Evidence layout

All paths below are relative to field-runs/.

- apps/<app>/ENV.md: measured machine and runtime details, setup source and constraints.
- apps/<app>/metadata.json: pinned source URL and SHA, shape, mechanically counted size.
- apps/<app>/commands.sh: exact commands actually executed, not a proposed recipe.
- apps/<app>/stages.json: status, reason and evidence for every stage.
- apps/<app>/logs/: raw stdout, stderr, baseline RSpec JSON, timing and resource logs.
- apps/<app>/reports/<scenario>/report.json: original unmodified saboteur report.
- apps/<app>/reports/<scenario>/measurement.json: command, kind, status, timing, exit code, identities and evidence paths.
- apps/<app>/triage.csv: scenario,mutant_id,file_line,classification,evidence_path.
- apps/<app>/kills.csv: scenario,mutant_id,file_line,cause,evidence_path,issue_url.
- apps/<app>/verification/: selected IDs, added specs, original and mutant outputs, verdict diffs.

Allowed triage classifications: real gap, equivalent mutant, false survivor, environment noise. Allowed kill causes: assertion failure, exception, DB/infrastructure error, timeout. Infrastructure failures are counted as fake kills. Missing CSVs mean verification unknown, not no findings.

Each app has a four-hour execution bound. Stop and report when it passes that bound. Follow the documented install and whole-suite-map flow unchanged. Any failure of that flow is a finding, not permission to silently work around it. No saboteur product changes are made here.

Check the report generator before use:

```sh
ruby -c script/summarize.rb
ruby test/summarize_test.rb
```

A command measurement's `status` records its exit outcome only. Stage completion belongs in stages.json and requires the stage's full evidence. The optional script/measure.py records wall time, exit and peak child RSS on Linux; its peak-RSS measurement is not a whole-machine or simultaneous-worker total. Record the operating system, and do not compare incompatible memory measurements.

Additional synthetic-only contract checks (Python 3 and Ruby on PATH):

```sh
python3 test/independent_test.py
python3 test/measure_test.py
```

These tests create temporary fixtures, not app findings. The independent test
accepts a `RUBY` environment variable pointing to a Ruby executable.
The generator rejects duplicate mutant/test IDs, duplicate CSV scenario/ID pairs,
unknown verification classes and CSV IDs that do not match PR report verdicts.
CSV evidence paths are references, not proof that verification succeeded: a
reviewer still needs to inspect the source artifacts. Empty or header-only
verification CSVs remain unknown, rather than proving there were no fake kills.

`--select` does not freeze an empty sample before any PR report exists. After
PR reports exist, it creates missing verification directories and records a
SHA-256 of the full candidate pool, so later pool changes cannot silently reuse
an earlier sample. Run selection only after the intended PR reports are ready.
This guard does not certify that all requested PR runs have been completed.

Verdict comparisons include mutant identity/location, status, killing test
names, classifications, observed-value state, confirmation and kill-cause fields.
They exclude runtime and local test-table allocation IDs. A zero diff is only
agreement of these recorded semantic fields, not proof of equal performance,
whole-suite correctness or independent verdict verification.
