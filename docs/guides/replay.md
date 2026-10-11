# Replay one mutant

Copy the full 16-character digest from a survivor or the JSON report:

```sh
bundle exec saboteur run --id 1a2b3c4d5e6f7a8b --seed 42
```

The digest above is an example. Use a digest from your own current source.
Keep the source, config, dependencies and seed the same as the original run.

`--id` resolves exactly one current mutant within the configured include files
and any `--subject` or `--since` filters. Prefixes, unknown digests and ambiguous
digests are errors (exit 2). Changed source or mutation-source config can make an
old digest unavailable.

Replay bypasses the per-method cap, coarse-survivor gating, incremental verdict
reuse and the ignore list. It runs that mutant with its coverage-selected tests,
using the normal timeout and unchanged-method verdict checks. A coverage build
may run the whole suite first; those baseline checks are not extra mutants.
Test ordering starts from the coverage map rather than earlier mutants' killer
history. Replay does not reproduce timing or previous killer-first ordering.

A surviving replay exits 1 even if the digest is in the ignore list. Killed or
timeout results exit 0; a tool error exits 3. Existing terminal and JSON reports
contain only the selected mutant. An uncovered mutant is reported as skipped.
