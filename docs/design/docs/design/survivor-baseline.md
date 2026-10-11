# Survivor baseline gate (design for review)

Status: proposal, not shipped. This changes no default run behavior. The goal
is "no new survivors" for a named, repeatable scope, not a passing score.
An accepted survivor is still a survivor and still enters the score.

## Boundaries

A survivor baseline records human decisions. ResultCache records potentially
reusable verdicts. Neither is the unchanged-suite baseline check. Keep all
three separate. Never turn a baseline entry into a cached verdict or skip.

Version one supports whole configured projects and explicit subject filters.
It refuses `--since`, replay and incremental verdict reuse. A diff from one
PR is not the same scope as a diff from another PR. A later diff-aware gate
would need a paired, exact-base candidate universe, not two diff scores.

In baseline mode all valid selected candidates run, including fine candidates
after a coarse survivor. The configured cap is retained but any truncation
makes the gate incomplete. Users can raise the cap or narrow their scope.
Uncovered subjects/candidates, runtime skips, errors, resource stops, invalid
execution evidence and changed-during-run inputs also make it incomplete.
An empty scope is not a clean gate. Invalid proposals rejected by the parser
are counted separately; they are not runnable candidates.

## Identity and compatibility

Do not change the existing 16-hex ignore/replay digest. Add baseline identity
version 1: a full SHA-256 of a canonical JSON tuple containing repository-
relative file path, subject ID, source identifier, operator, coarse flag and
sorted edits (subject-relative byte range, original bytes and replacement).
Include edit lengths; JSON encoding avoids delimiter collisions. Require
edits in the subject's file and reject paths outside the project root.
Absolute checkout paths and line numbers are not identity. Moving a file or
renaming a subject changes identity; adding lines elsewhere does not.

Store the readable identity tuple alongside the hash and validate both.
Record a full subject-source SHA-256 as acceptance context, distinct from
mutant identity. If a method changes, even a surviving identical local edit
needs review again. Two definitions with the same file/subject ID are
ambiguous and fail closed. Duplicate mutant IDs fail closed too.

A versioned manifest records:

- baseline format and identity versions;
- saboteur/generator version and configured source identities/content hashes;
- canonical effective comparison config and scope (include, exclude, subject
  filters, mutation settings, integration, boot/hooks, RSpec args, seed and
  execution limits), with a documented list of excluded output/cache paths;
- Ruby engine/version/platform;
- selected subject inventory and every generated valid selected candidate;
- input snapshot fingerprint, source/dependency provenance, completion
  evidence and accepted survivor entries with nonblank reasons.

Comparison requires equal identity/generator/runtime versions and canonical
comparison config/scope. Inventories need not be equal: added code can create
new candidates. Project/test/dependency content fingerprints are provenance,
not cross-run equality: changing tests is exactly how a survivor gets killed.
Changed custom generator content is incompatible, not a new-survivor count.
Unknown versions, malformed entries and missing metadata are errors, never
empty baselines. Do not silently migrate older baselines.

## Complete evidence, independent of acceptance

Capture the planned candidate IDs before execution. Reconcile them with
final results: exactly one terminal result per candidate, no missing or extra
IDs. Carry explicit typed completeness reasons through Report rather than
infer completeness from zero survivors or parse warning text. Carry skipped
subjects and cap counts separately. Complete means the unchanged suite was
green and stable, planned candidates were all tested, and input verification
passed. Baseline mode must not claim complete using legacy Stryker JSON.

Reuse the engine lane's RunFingerprint snapshot-then-verify vocabulary and
implementation once available. Snapshot before mutation execution; verify
before producing acceptance-ready evidence. Unreadable inputs or changing
inputs block acceptance and clean comparison, even if a fresh verdict run
can still be useful. External DB/network/time/environment state cannot be
proven stable by file hashes; document that limit. No duplicate cache writer
or new cache format in this feature.

## Comparison output and exits

Classify independently and list deterministically by file, subject, ID:

- accepted survivors: exact identity and unchanged acceptance context;
- new survivors: current survivor identities absent from the baseline;
- changed survivors: identity exists but acceptance context changed;
- resolved entries: previously accepted candidate now killed or timed out;
- unmatched entries: accepted identity no longer generated, or file/subject
  missing. Never call these resolved or automatically carry their acceptance;
- incomplete evidence, errors and compatibility failures.

Baseline ignores neither errors nor gaps. Existing ignore entries do not
hide new/changed survivors or make an incomplete gate pass. Reasons from an
ignore file are not automatically baseline approval. Scores are unchanged.

Exit 0 only for compatible, complete runs with no new/changed survivors and
no unmatched accepted entries. Exit 1 for reviewable regressions/stale
acceptance; exit 2 for malformed baseline/config or incompatible scope;
exit 3 for incomplete run/tool evidence. Incomplete wins over survivor
counts. JSON and terminal output include each category and gate state; the
normal run exit policy is unchanged outside this opt-in mode.

## Explicit proposal and acceptance

Proposed CLI (subject to panel review):

1. `saboteur run --baseline BASELINE.json` checks without writing the baseline.
2. `saboteur baseline propose --output PROPOSAL.json` runs the same exhaustive,
   fresh scope and creates a new proposal only after complete evidence.
   Existing output paths are refused. Survivors start with empty reasons.
3. A person reads diffs, supplies a reason for each survivor and reviews the
   proposed removals/changes in version control.
4. `saboteur baseline accept --proposal PROPOSAL.json --output BASELINE.json`
   validates evidence, identities and every reason. To replace an existing
   baseline it also requires `--previous-sha256 HASH`, matching the file
   reviewed. No force flag, automatic promotion or silent overwrite.

A proposal records the previous baseline hash (or explicit initial state)
and a content hash of the complete immutable run evidence; edits are allowed
only to acceptance reasons. Accept validates this binding and rechecks the
local input snapshot. Stale or edited evidence requires a fresh proposal.
Use strict bounded JSON validation, an advisory lock, exclusive creation for
new paths, and same-directory temp+atomic rename for reviewed replacements.
Check the previous hash under the lock. A failed accept leaves the old file
unchanged. Never accept an imported unverified report. Reasons are human
judgment, not a proof of equivalence. Version control review remains a team
responsibility, not something a local command can enforce.

## Delivery and tests

Land design before implementation. Wire opt-in completeness and exhaustive
scheduling first, then identity/manifest/comparison, explicit acceptance,
CLI/reporting and README/guide. Coordinate CLI and Report changes with the
other lanes. No mutineer implementation is copied or consulted for this.

Tests must cover a same-scope unchanged acceptance, a newly added survivor,
changed context, file/subject rename, killed versus missing entries,
duplicate identities, malformed/version/config/generator mismatches, capped
and uncovered runs, coarse-survivor fine execution, partial worker failure,
ignored survivors, snapshot drift, blank reasons, tampered/stale proposals,
initial exclusive create, concurrent replacement hash conflicts and failure
preserving old bytes. Dogfood changed code with no new ignore entries.
