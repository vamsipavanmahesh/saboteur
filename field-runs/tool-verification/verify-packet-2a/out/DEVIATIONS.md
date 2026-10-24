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

## 2026-10-24 ~07:51 gem "saboteur", path: /home/sandbox/verify/saboteur-src added to all 4 tree Gemfiles
Reason: bundle exec requires saboteur in the bundle; rubygems binstub blocks activation outside the bundle. Path gem = exact pinned source (git HEAD 6f87ccc98377bf0c23f3cf409006f0464c2aa67c, status clean). Gemfile.lock diff = 11 insertions, 0 deletions (PATH block + DEPENDENCIES line); no locked version changed. Verification wrapper only; no app change. Class: same as fiddle.
Consequence: bundle exec saboteur 0.12.3 runs lockfile-pinned in all 4 trees (loaded-specs manifests captured).

## ~07:55 confirm2.sh (bare-context) killed mid-2204-mutant-phase
Interrupted by design after bundle exec route landed; completed artifacts preserved (e4679d48 redo-2 exit=0, 856-test map green). Superseded by confirm3.sh (bundle exec, --verbose, --json per run).

## Bare-context results retained as NON-LOCK-PINNED
out/loaded-deps-proof.txt: bare runs in tree-2090 resolved rails 8.1.3.1 et al (lock=8.0.5) due to shared GEM_HOME; 2204/2156/2231 bare runs diverged only on bigdecimal/matrix(/brakeman). bundle exec reruns are the authoritative set.

## 2026-10-24 10:03 - verifier transcription bug: 6 mutant IDs fabricated in confirm3/confirm6 scripts
When rewriting the rerun script after compaction, six 2204 kill IDs were re-typed from memory with WRONG final-8 hex (e.g. 04d209540e2a4e57 instead of pool-frozen 04d20954d514506c). Those 6 replays exited 2 ("mutant not found in the selected current source") - a verifier bug, NOT a tool or environment problem. The pool file (SHA256 bfe86e3f...) and the original bare-context rerun script carry the correct IDs; the bare reruns validly reproduced those kills at 07:35-07:44. Corrective: confirm7.sh reruns the 6 with IDs extracted programmatically from the frozen pool. All other 8 of 14 IDs verified against the pool/reports as correct.
