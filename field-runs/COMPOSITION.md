# Evidence composition notes

Raw application logs, RSpec JSON and source measurement records are retained. No baseline or mutation exit code was adjusted. No app baseline was rerun during report composition.

Source stage envelopes were normalized to the flat stages mapping expected by the report generator. Original source stage files remain alongside them. Later stage labels distinguish unstarted versioned work from completed preparation measurements.

Solidus per-tree measurement records gained evidence_paths pointing to their existing RSpec JSON/logs; originals remain measurement-source.json. Their numeric fields were not changed. Baseline-red IDs were extracted from original RSpec JSON into baseline-red-candidates.json and are not actual mutation exclusions.

Published replay instructions distinguish grouped provisioning recipes from literal command history. Original supplied command descriptions are retained as source files where the composed wording changed. The helpers were not rerun from the final evidence directory. Unsupported runtime relocation and setup deviations remain visible.

Memory measurements are method-dependent: Lobsters uses peak child RSS from RUSAGE_CHILDREN; Chatwoot and Solidus sample the RSpec process and direct children, not all descendants or database services. Neither approach gives whole-machine memory cost. Sampled maxima can miss peaks. Timing methods and RSpec example duration are separate and must not be interchanged.

The report generator was independently checked with synthetic fixtures and actual baseline inputs. This verifies evidence-tool behavior, not saboteur compatibility, complete PR coverage, app setup equivalence or mutation verdict correctness. No triage outcome exists without raw versioned mutation reports.
