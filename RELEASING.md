# Releasing

Releases are published by GitHub Actions (`.github/workflows/release.yml`).

1. Update `lib/saboteur/version.rb` and add a `## [X.Y.Z] - YYYY-MM-DD`
   section to `CHANGELOG.md`.
2. Push to `main`.

When CI passes on that commit and version X.Y.Z is not on RubyGems yet, the
workflow builds and pushes the gem, tags the commit `vX.Y.Z` and creates the
GitHub release from the CHANGELOG section. A push that does not change the
version publishes nothing.

## Release gate

Before any release:

1. `rake release:check` must pass. It runs the unit suite, `spec/e2e`,
   `rake acceptance` and `rake claims:check`, and prints a one-page summary.
2. A reviewer report (see `docs/agents/reviewer.md`, run in a fresh context)
   must have no open blocker for the release candidate.
3. Batch work: at most one release per review round.
4. Update `docs/harness-metrics.md` with the release's three counters,
   per release and cumulative.

An acceptance scenario that fails is listed in the release notes as a known
gap, never edited to pass.

## One-time setup

The workflow uses RubyGems trusted publishing (OIDC), so no API key is stored.

1. On rubygems.org, add a trusted publisher for the `saboteur` gem (a
   pending publisher, before the first release): repository
   `vamsipavanmahesh/saboteur`, workflow `release.yml`, environment `release`.
2. In the GitHub repository settings, set the Actions variable
   `PUBLISH_GEMS` to `true`. Until then the release job is skipped.
