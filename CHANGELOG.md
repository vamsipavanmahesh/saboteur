# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `saboteur run` with `--since`, `--subject`, `--timeout-factor`, `--jobs 1`,
  `--reeval`, `--json`, `--no-cache`, `--config`.
- Subject finder (Prism) and the v1 operators as byte-range edits: coarse
  `nil`/`raise` bodies first, comparison, boolean, arithmetic, numeric
  literal, statement removal, safe navigation, `||=`.
- Per-mutant test selection by line coverage, prior killers then fastest
  first; coverage map cached by content hash.
- Neutral check before mutating each method.
- Supervised children: whole-tree tracking and kill, deadline, memory and
  process caps, CPU-limit backstop, recursion guard.
- RSpec adapter; optional Rails profile (in progress). Minitest is out of
  scope for v1.
- Terminal report with unified diffs, Stryker JSON report, ignore list with
  mandatory reasons.
- Mutation-source extension point and lifecycle hooks.

## [0.0.1] - unreleased

### Added
- Gem skeleton to reserve the name: CLI argument parsing, integration adapter
  and hook interfaces, mutation-source extension point. No mutation testing yet.
