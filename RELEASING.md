# Releasing

Maintainers only. Requires rubygems MFA.

1. Update `lib/saboteur/version.rb` and `CHANGELOG.md`.
2. `bundle exec rake` (specs + rubocop).
3. `gem build saboteur.gemspec`
4. `gem push saboteur-X.Y.Z.gem`
5. `git tag -s vX.Y.Z && git push --tags`
