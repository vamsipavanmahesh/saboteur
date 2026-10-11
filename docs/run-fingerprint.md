# Declared run-input fingerprint contract

`Saboteur::Engine::RunFingerprint` is a read-only building block, not a cache
policy, baseline gate or dependency graph. This PR does not enable cache reuse.

```ruby
fingerprint = Saboteur::Engine::RunFingerprint.new(
  config: config, root: config.root, extra_files: [],
  runtime_identity: Saboteur::Engine::RunFingerprint.runtime_identity
)
before_boot = fingerprint.snapshot
verification = fingerprint.verify(before_boot)
```

Capture before loading target code. Keep that snapshot unchanged. Verify after
baseline/coverage and before reuse or saving cache entries. Consumers must require
both `complete` and `unchanged`; a digest alone is not permission to reuse. A
changed input should disable reuse or abort the affected workflow, never silently
replace the pre-boot snapshot. Additional discovered inputs go in `extra_files`
before capture; discovering them only after boot is not evidence that the original
snapshot covered them.

Snapshot (immutable Data value): `format_version`, `digest`, `inventory`,
`settings_digest`, `runtime_digest`, `complete`, `issues`. Verification:
`unchanged`, `complete`, `current_digest`, `changes`, `issues`. Each change has
`path` and `reason` (`added`, `removed`, `changed`, `unreadable`). No contents,
configuration values or secrets are returned in change explanations.

Inventory entries have `path`, `kind`, `state`, `sha256`, `required`. Paths are normalized
project-relative paths, or `external:<absolute-path>` for explicit outside inputs.
Kinds are `ruby`, `manifest`, `boot`, `hook`, `source_plugin`, `extra`. States are
`present`, `missing`, `unreadable`. Missing dependency/option manifests are allowed
and hashed as missing so their later creation changes the digest; missing explicit
boot/hook/source/extra files are incomplete. Entries are deduplicated by path and
sorted. Settings and injected runtime identity are hashed with sorted mapping keys.
Lists preserve order. Format version 1 describes this fingerprint, not cache format
2 or the Stryker/public report schema.

The declared model includes all project `.rb` files, regardless of mutation include,
exclude or diff scope; Gemfile, gems.rb, both lockfiles, .rspec and .rspec-local;
explicit boot/hook/source-plugin/extra paths; effective config except cache/report destination paths; Ruby engine/version/
patchlevel/platform and saboteur version. It does not follow directory symlinks:
a discovered project symlink marks the snapshot incomplete. Unreadable files or
directories likewise make it incomplete. It excludes `.git`, `vendor`,
`node_modules`, the configured cache directory and configured report output paths.
These exclusions are boundaries, not discovered safe dependencies.

Installed/vendor gem contents and resolved bundle identity are NOT discovered by
this class. A consuming gate must establish that policy and pass dependency
identity in `runtime_identity` or explicit content paths before claiming coverage.
Local/path dependencies, external option requirements and non-Ruby fixtures need
explicit `extra_files` or a stricter consumer inventory. No claim covers arbitrary
ENV, database, network, time, external services or concurrent edits during hashing.
Inputs must stay immutable throughout loading and execution. Snapshot-then-verify
detects observed drift, not a transaction over the application filesystem.

For optional absent config files, `extra_files` accepts
`{ path: ".saboteur.yml", required: false }`. The missing marker is hashed and
its later creation changes identity. A plain path remains required. Serialize with
`Snapshot#to_h` (JSON-safe nested entries), and reconstruct with
`RunFingerprint.restore_snapshot(JSON.parse(bytes))`. Restore validates types,
version, entry paths and the claimed digest; invalid evidence raises ArgumentError.
Issues are sorted unique strings. Changes are sorted inventory paths followed by
settings/runtime changes. Configured cache roots overlapping root/app/lib/spec or
explicit inputs and report paths overlapping explicit inputs/Ruby files make the
snapshot incomplete, not silently safe. Consumers must also reject artifact aliases
and symlink/hardlink destinations before writes; this read-only class does not grant
safe write destinations or offer arbitrary artifact exclusions.

Checkout root and configured artifact paths use the same canonical path basis,
including existing symlink ancestors of missing destinations. Settings identity
excludes `cache_dir`, `json_report` and `html_report`; overlap checks still inspect
them. Restore accepts only normalized relative inventory paths or normalized
`external:/absolute` paths, known kinds, and present entries with a SHA-256 hash
(missing/unreadable entries must have no hash).

Duplicate explicit paths merge their required flags with OR. A required boot/hook/
source role cannot become optional by being listed again as an extra file. Roles
use the lexically first non-extra role when several apply. Identity mappings reject
Symbol/String collisions after key normalization and reject non-JSON values and
non-finite numbers. Restored issues must be sorted unique strings; a complete
snapshot cannot contain unreadable entries even if its issues list was altered.
Fixed manifests are protected from report-output overlap too.

Explicit root must realpath to Config.root; differing roots raise ArgumentError.
Report paths naming existing directories are unsafe. Cache directories inside or
above app/lib/spec or explicit required inputs are unsafe. Entry `required` is a
Boolean preserved in evidence so restored complete snapshots cannot hide missing
required extras. Missing optional extras/manifests remain valid missing markers.
