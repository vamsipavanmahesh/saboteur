# Releasing

Releases are published by GitHub Actions (`.github/workflows/release.yml`).

1. Update `lib/saboteur/version.rb` and add a `## [X.Y.Z] - YYYY-MM-DD`
   section to `CHANGELOG.md`.
2. Push to `main`.

When CI passes on that commit and version X.Y.Z is not on RubyGems yet, the
workflow builds and pushes the gem, tags the commit `vX.Y.Z` and creates the
GitHub release from the CHANGELOG section. A push that does not change the
version publishes nothing.

## One-time setup

The workflow uses RubyGems trusted publishing (OIDC), so no API key is stored.

1. On rubygems.org, add a trusted publisher for the `saboteur` gem (a
   pending publisher, before the first release): repository
   `vamsipavanmahesh/saboteur`, workflow `release.yml`, environment `release`.
2. In the GitHub repository settings, set the Actions variable
   `PUBLISH_GEMS` to `true`. Until then the release job is skipped.
