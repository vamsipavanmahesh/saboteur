# Lobsters hosted run recipe (preparation draft)

Status: not run-proven. No native Ruby, Bundler, saboteur, map or replay has been executed from these bytes.

Method label: July own-HEAD map plus PR replay, rebuilt in a new hosted environment (GitHub ubuntu-latest, Ruby 4.0.0, sqlite3). Not byte-comparable with the July sandbox runs and not homogenized with the September flow.

Scope facts
- Controls (head and base, seed 3, fresh DB) run on the INSTRUMENTED trees only. They are admission controls, not a qualification. Original-tree full-suite controls are not part of this recipe.
- Instrumentation, the two added gems (fiddle, saboteur) and any lock checksum additions are disclosed in out/deps (original, patched, installed locks and diffs).
- Map: saboteur run --all --verbose --jobs 1 --no-cache --seed 3, stopped at a validated map boundary (64-hex key, coverage format 11, inputs format 2, map_digest linkage). Exit 130 is a deliberate stop, never a suite pass.
- Replay: saboteur run --since BASE --baseline-passes 1 --max-duration 10m --jobs 1 --verbose --seed 3 after a fresh DB. The 10m cap is never shrunk; the job stops before it if time is short.
- Config: partial_coverage = "use" restores the agreed protocol intent. The original July config bytes were not recovered; the settings digest cannot prove the field.
- Timeout or deadline stops normalize to exit 124 whatever the child did on its stop signal.
- Scope: mutation scope is app/**/*.rb. The measured app Ruby changes (2178 token.rb, 2158 comment.rb) are in scope; the 2158 brakeman ignore and config files are outside mutation scope. mr.sh writes changed-files.txt and changed-ruby-scope.txt as the inventory; the producer's earlier out-of-scope note for those two .rb files is superseded by QA/principal review.
- A boundary stop (exit 130) with log lines about baseline completion or subject counts is evidence of the stop only. It is not row qualification or study admission.
- Boundary identity: inputs.root must equal sha256 of the canonical app root and seed must equal 3; runtime and settings digests are compared with values computed at setup from the pinned tool's own constants (CoverageStore::CACHE_INPUTS, CoverageInputsSnapshot.runtime_digest); this comparison is untested against a real Ruby run. The triple's bytes are re-hashed before the stop and compared again after it.
- The recipe commit/tree are frozen constants in the workflow file and are empty until the reviewed head exists.
