# Solidus field-run environment

- App: solidusio/solidus, pinned SHA 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8 (2026-10-20T14:12:09-07:00, merge of PR #6705)
- Repo shape: multi-gem engine (core, backend, api, admin, promotions, sample, storefront); suite under test: `cd core && bundle exec rspec` (README "Run an individual test suite"), SQLite 3 default
- OS: Ubuntu 22.04.5 LTS, kernel 6.1.158+ x86_64
- CPU: 2 cores; RAM: 1.9 GB total (~1.7 GB available); swap: 0
- System sqlite3 CLI: 3.37.2 (spec DBs use the sqlite3 rubygem)
- Ruby: 3.4.6 (2025-09-16 revision dbd83256b1) +PRISM [x86_64-linux], ruby-builder toolcache tarball (built for prefix /opt/hostedtoolcache/Ruby/3.4.6/x64) relocated to /home/sandbox/ruby34cache/3.4.6/x64.
  DEVIATION (unsupported configuration): the prefix string was patched IN-PLACE inside bin/ruby and libruby.so.3.4.6 with an equal-length replacement (35 bytes) plus matching edits to rbconfig.rb/pkgconfig/bin-shebangs. This is a hand-modified binary runtime, NOT an officially supported install; ruby-builder/rvm/ruby-install do not document this relocation as supported.
  Probes passed before baseline (exact list): ruby --version; $LOAD_PATH has all 8 expected entries; 43 stdlib/default-gem requires all OK; default versions outside bundler json 2.9.1 / psych 5.2.2 / openssl 3.3.0; bundle install completed (202 gems, psych 5.5.0 native ext compiled); under bundle exec, psych 5.5.0 loads from the lockfile-pinned gem path (no default-gem shadowing); smoke specs: spec/lib/spree/core/version_spec.rb (3 examples, 0 failures), spec/models/spree/address_spec.rb (36 examples, 0 failures, exercises DummyApp boot + sqlite auto-migrate).
  Remaining uncertainty: these probes do not establish full equivalence with an officially supported install. Untested stdlib/native-extension surface may behave differently; any test failure whose cause is ambiguous MUST be treated as environment-suspect and cross-checked (e.g. rerun in isolation) before being attributed to the app or to saboteur. The earlier broken relocation (load-path truncation + gem shadowing) was found only by probing, so absence of symptoms is not proof of correctness.
- RubyGems 3.6.9; Bundler 2.6.9; git 2.34.1
- libyaml: sandbox has no system libyaml headers; Ubuntu 22.04 libyaml-0-2/libyaml-dev debs extracted user-space to ~/sysroot (PKG_CONFIG_PATH + LD_LIBRARY_PATH set) so psych 5.5.0 native ext compiles. Documented deviation; no app or Gemfile change.
- Toolchain validation before baseline: 43 stdlib/default-gem requires all OK; versions json 2.9.1 / psych 5.2.2 / openssl 3.3.0 outside bundler (expected defaults); bundle exec psych check below.
- saboteur version: null (0.13.0 not released at prep time; SHA pending from main)
- Dummy app: boots in-process via core/spec/rails_helper.rb (DummyApp.setup + auto_migrate); no separate documented setup step for the core suite
- F-ENV-1 (documented-flow gap): the README core-suite path needs a system libvips that is never mentioned; without it, 8 image-variant specs fail (see findings.md). CI installs libvips out-of-band.
