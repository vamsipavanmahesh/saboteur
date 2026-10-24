# PR2231 independent targeted crash-kill verification

This verifies four reported crash kills only, not whole-suite map completeness,
selected-map protocol adequacy, other PRs, survivor noise, performance or all-45
study completion. Zero survivors gives an undefined survivor-noise rate, not 0%.

## Grounding and environment

Era checkout: lobsters/lobsters at 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8.
Parent: 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c.
Source-pinned saboteur: 6f87ccc98377bf0c23f3cf409006f0464c2aa67c.
The supplied locally built artifact identifies as 0.12.3, not a newer release.
Artifact SHA256: 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa.

Fresh Linux x86_64 environment, Ruby4.0.0 official ruby-builder prebuilt archive,
Ubuntu22.04, SQLite. No binary prefix patch. Environment variables relocate
library/gem lookup and scripts are invoked with the actual Ruby executable.
Libyaml headers apt-extracted locally for psych; libvips8.18.7 from sharp's
1.3.4 Linux-x64 package. No paid infrastructure or user-device changes.

The supplied as-run lock carried a registry checksum that differs from the
locally built artifact. It was not used to suppress validation. The final probe
started again from the era's original lock; `gem install --local` installed the
immutable supplied artifact, then `bundle install --local` regenerated the lock.
Final dependency changes are fiddle and saboteur additions only. No PATH
source dependency or disabled checksum validation is used by these checks.
An earlier path-source exploratory install was discarded before measured cases.
Three-way per-file hashes match installed code, artifact contents and pinned
source: 234 lib files, and all 238 packaged files. The local artifact itself was not rebuilt or changed by this verifier.

No app/spec files were edited except each temporary report-defined mutation.
The generated database.yml is the unmodified repository sample. DB preparation
is local to this disposable checkout. No exclusion or unrelated spec changes.

## Procedure

verify_crash_kills.py reads the four IDs from source-report.json, resolves
killedBy through testFiles, and applies exactly the report replacement over its
1-based location range. applied.diff records the concrete hunk. Each selected
example is run in a separate RSpec process with seed20261024, JSON output and
combined stdout/stderr. Sequence per case: unchanged original, mutant, restored
original. No whole-suite map or saboteur engine replay was rerun.

Each case produced one original example PASS (exit0), one mutant example FAIL
(exit1), then the same restored example PASS (exit0). Original/restored source
hashes match. Final app/spec git diff is empty. receipt.json contains actual
argv, wall duration, file hashes, summaries and failure exception/backtrace;
original.json, mutant.json and restored.json are raw RSpec results.

## Findings

- de58186074f0256b, body_nil, email_reply_mailer_spec.rb[1:1]: NoMethodError,
  undefined method map for nil at email_reply_mailer.rb:42. The mutated parents
  returns nil to the mailer. Genuine mutation-induced exception kill.
- a40b6c227630d3c3, body_raise, same mailer example: RuntimeError at
  comment.rb:466, then email_reply_mailer.rb:42. Genuine explicit-raise kill.
- 5ea32ddfa7071c31, statement_removal, comment_spec.rb[1:10:3]: NoMethodError,
  undefined method ids for nil at comment.rb:261. Actual report replacement is
  literal nil over the recursive-query chain, leaving the earlier conditional
  return intact. Genuine mutation-induced exception kill.
- 46132a2113f3aa6c, pair_removal, same comment example: ArgumentError,
  The method .order() must contain arguments, at comment.rb:475, then261.
  Removing depth: :asc leaves empty .order(). Genuine argument-validation kill.

All four classes match the original report's statusReason. No setup/database
failure appears in these targeted failing example bodies. This supports four
genuine exception kills under this probe environment, not four assertion kills.
No survivor classification, top survivor finding or numeric noise estimate is
available from this four-kill verification.

## Reproduction notes

Source env.sh after placing the runtime/dependencies under its recorded root,
then run python3 verify_crash_kills.py against the pinned disposable checkout.
Absolute paths in the captured argv are intentional evidence, not a portable
installer. Copying the script requires changing ROOT/env paths and providing the
same app era, runtime, artifact, dependency lock and local databases. Source URLs:
https://github.com/lobsters/lobsters
https://github.com/vamsipavanmahesh/saboteur
https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.0/ruby-4.0.0-ubuntu-22.04-x64.tar.gz
https://registry.npmjs.org/@img/sharp-libvips-linux-x64/-/sharp-libvips-linux-x64-1.3.4.tgz
