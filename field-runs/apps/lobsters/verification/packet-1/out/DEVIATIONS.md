# Independent verifier environment deviations (no app code or app spec edits)

Box: Ubuntu 22.04.5 sandbox, 2 CPU, 1.9GB RAM, no sudo - same class as producer's.

1. Ruby 4.0.0: ruby-builder prebuilt ubuntu-22.04 tarball (official), text-script
   shebangs repointed to /usr/bin/env ruby (tarball targets a toolcache path).
   Same class of deviation as producer's documented ruby-4.0.9 install.
2. Local header/lib extracts (no sudo): libyaml-dev/libyaml-0-2 (psych native build),
   libffi-dev/libffi8 (fiddle native build) via apt-get download + dpkg -x.
3. libvips 8.18.7 from sharp's official @img/sharp-libvips-linux-x64 1.3.4 npm tarball,
   symlinked as libvips.so.42 (mirrors producer ENV.md; jammy's 8.12.1 is rejected by Rails 8.1).
4. gem "fiddle" appended to each verification tree's Gemfile (+bundle install):
   Ruby 4.0 makes fiddle a bundled gem; saboteur refuses to run its sandbox layers
   without it in app children (exit 3 otherwise). Environment fix, not an app change.
   Recorded per main's earlier acceptance of this exact deviation.
5. D-ENV-1 (matches producer's fix, proven before/after in cgi-denv1-trace.txt):
   ruby tree's stdlib cgi.rb removal-shim renamed aside so the Gemfile's cgi 0.5.1
   gem resolves; github_spec sentinel then passes 2/0. No app files touched.
6. config/saboteur.rb written per tree: include app/**/*.rb (replicates Rails
   auto-detection) + rspec_args --exclude-pattern spec/features/user_administration_spec.rb
   (EX-1, user-approved 06:52 via main). NO other exclusions. An EX-2 github_spec
   exclusion was drafted, STOPPED before any run used it, and reverted (07:44-07:45).

NOT done: no edits to any app source or existing app spec file; no changes to
Gemfile.lock content beyond the fiddle addition; no app config edits (database.yml
created by the app's own bin/setup from its database.yml.sample).

Gem provenance: saboteur 0.12.3 built locally from pinned source
6f87ccc98377bf0c23f3cf409006f0464c2aa67c; my gem sha256
16ef8af613ad2d1e010e08c585586807aaa2a33ac0f604d5828236981b63c9a1 differs from
producer's published 7f5b8949... (gem build not byte-reproducible; same source commit).
