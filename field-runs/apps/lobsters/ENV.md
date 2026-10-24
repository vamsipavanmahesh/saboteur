# Lobsters environment (field-run app environment)

- App: https://github.com/lobsters/lobsters
- Pinned SHA: 407536444934ac7d78f4ce1c18f228e3891a8663 ("bump for Ruby joining this week's CVE-a-thon", 2026-10-23 10:06:27 -0500, = origin/main HEAD at qualification)
- Qualification source: 488 tracked Ruby files, 109 *_spec.rb files, Rails 8.1.3.1 + rspec-rails 8.0.2, SQLite (app-compiled), Ruby 4.0.9 per .ruby-version
- Machine: Linux x86_64 sandbox container, Ubuntu 22.04.5 LTS (jammy), 2 CPUs, 1.9 GB RAM, no sudo, no paid infrastructure
- Timebox: 4h from 2026-10-23 21:39 IST (prep start); saboteur 0.13.0 measurements held until release SHA verified by main

## Documented setup (CONTRIBUTING.md "Setting up your environment") - NOT completed unchanged

The documented flow was BLOCKED at two points on this machine and only completed after the
recorded deviations below. The final successful setup is therefore "documented flow + recorded
deviations", not the documented flow verbatim.

1. "Install the Ruby version specified in .ruby-version" = 4.0.9.
   No sudo/apt possible; used the official ruby-builder prebuilt of the EXACT documented version:
   https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.9/ruby-4.0.9-ubuntu-22.04-x64.tar.gz
   -> ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux], RubyGems/Bundler 4.0.20, OpenSSL 3.0.2.
   bin/* shebangs repointed to /usr/bin/env ruby (tarball targets a GitHub-hosted-toolcache path).
2. "Install libvips" (doc command: sudo apt install libvips).
   FINDING F-ENV-1: Ubuntu 22.04's packaged libvips is 8.12.1; Rails 8.1 refuses to boot with it
   ("libvips's unfuzzed operations are not safe... requires libvips 8.13 or later"). So the documented
   apt command is insufficient for this app on Ubuntu 22.04. Recorded as an environment finding.
   Resolution used (explicitly documented, not silent): prebuilt libvips 8.18.7 from sharp's official
   @img/sharp-libvips-linux-x64 1.3.4 npm tarball (lib/libvips-cpp.so.8.18.7 symlinked as libvips.so.42),
   verified loaded and reporting 8.18.7 via ruby FFI.
   (An intermediate step also apt-extracted jammy libvips42 8.12.1 + deps locally; superseded by 8.18.7.)
3. Missing system headers for native gems (no sudo): psych 5.3.1 needs yaml.h.
   Resolved by apt-get download libyaml-dev + libyaml-0-2, extracted locally, and
   `bundle config set --local build.psych --with-libyaml-include=... --with-libyaml-lib=...`.
   The app's own .bundle/config sqlite3 build flags were preserved unchanged.
4. `bin/setup` (idempotent by design) run 3 times: attempt 1 failed on psych/libyaml headers,
   attempt 2 failed on the libvips>=8.13 requirement (F-ENV-1), attempt 3 EXIT_CODE=0 at
   2026-10-23T21:50:59+05:30 after the recorded deviations above. Full log: logs/bin-setup.log.
   It created db/development/*.sqlite3 and db/test/*.sqlite3 and compiled sqlite3 with the repo's flags.

## Environment variables (~/field-runs/env.sh, sourced for every command)

- PATH: ruby-4.0.9/bin + its GEM_HOME/bin, then system
- LD_LIBRARY_PATH: ruby lib, sharp-libvips lib dir, apt-extracted lib dir
- RUBYLIB / GEM_HOME / GEM_PATH: ruby-4.0.9 tree (tarball prefix is not writable /opt)
- PKG_CONFIG_PATH / CPATH / LIBRARY_PATH: apt-extracted headers (libyaml) for native builds

## Not done (documented steps intentionally skipped)

- `rails credentials:edit`: not needed to run the test suite; no external-service keys used.
- `rails fake_data`: dev-sample data; not needed for RSpec baseline.
- No changes to app code, Gemfile, .bundle/config app flags, or any upstream file. No upstream PRs/issues filed
  (CONTRIBUTING forbids LLM-written code contributions; this run is local verification only).
