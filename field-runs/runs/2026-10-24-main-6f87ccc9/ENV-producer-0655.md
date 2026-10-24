# Lobsters field run — environment identity (fresh runtime, post-rebuild 2026-10-24)

## Runtime
- Box: 2 CPU / 1.9 GB RAM, Ubuntu 22.04.5 LTS, kernel 6.1.158+ x86_64 (e2b sandbox, rebuilt 2026-10-24 ~06:34 IST; all local state from earlier windows wiped and rebuilt)
- Ruby: 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux], ruby-builder prebuilt, extracted to ~/field-runs/ruby/ruby-4.0.9 (compiled-in prefix /opt/hostedtoolcache/... absent; RUBYLIB carries stdlib dirs)
- Ruby: 4.0.0 (ruby-builder prebuilt, ~/field-runs/ruby/ruby-4.0.0) for PR-era trees (.ruby-version 4.0.0)
- gem 4.0.20, bundler 4.0.3, sqlite3 3.37.2; libvips 8.18.7 via sharp tarball (no sudo); libyaml headers via apt-extract
- Git identity of lobsters pin: 407536444934ac7d78f4ce1c18f228e3891a8663 (2026-10-23, = origin/main at qualification)

## saboteur under test (identity for every report row)
- Source: https://github.com/vamsipavanmahesh/saboteur @ 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (main, verified live 2026-10-24 06:31 IST; fixed pin, repo main has since advanced via docs-only merges)
- Version verbatim from gemspec: 0.12.3
- Built artifact: saboteur-0.12.3.gem, sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa (504320 bytes)
- Installed from that artifact into both ruby GEM_HOMEs; runtime loaded-spec verified (GEM_HOME gems/saboteur-0.12.3); payload diff -r vs source checkout: zero differences (lib/, exe/)

## Deviations / exclusions (each also on affected report rows)
- D-ENV-1 (environment fix, 06:45 IST): ruby-builder Ruby 4.0.x ships lib/ruby/4.0.0/cgi.rb + cgi/ as the Ruby 4.0 stdlib removal shim; with RUBYLIB stdlib dirs it shadowed the cgi 0.5.1 gem -> CGI.parse undefined (false baseline failure F-BASE-1). Fix: renamed shim aside in both ruby trees (cgi.rb.removed-ruby40-shim, cgi.removed-ruby40-shim). No app code/spec touched. Side effect: bare `require "cgi"` outside bundler LoadErrors. Recipe recorded in rebuild.sh. Probes: logs/env-fix-before.log (PARSE=false) vs logs/env-fix-after.log (PARSE=true, VERSION=0.5.1 from gem path).
- D-FLOW-1 (documented install deviation): docs' `bundle add saboteur --group test` pulls from rubygems; per the pin-to-main rule the registry gem was NOT used. Installed the gem built from source SHA 6f87ccc9 via vendor/cache + `bundle install --local` (pin tree) and `gem install --local` into the ruby-4.0.0 GEM_HOME + bundler using the installed copy (PR trees), with loaded-spec + payload-diff verification.
- EX-1 (user-approved exclusion 2026-10-24 06:52 IST, field run only): spec/features/user_administration_spec.rb excluded via saboteur config `c.rspec_args = ["--exclude-pattern", "spec/features/user_administration_spec.rb"]` (no app file edits). Reason: "banning" example red on lobsters main @40753644, independent of saboteur (observed failing in 4 runs; non-flakiness not proven), untouched by any selected PR; likely related to lobsters issue #2263 (likely, not proven). Verified: suite expansion drops 913 -> 908 examples with the pattern; note rspec --exclude-pattern does not filter explicitly named file arguments, so a per-mutant run that names this file explicitly would still execute it.
- jobs control: generated config defaulted c.jobs=4; field rule is serial on this box - config set to c.jobs=1 and every measured command passes explicit --jobs (map/replays/determinism: --jobs 1; parallel stage: --jobs 2). Map attempt 1 (exit 5) ran with inherited jobs=4 before this control; noted on its row.
- F-ENV-3: kernel Landlock ABI 2 < required ABI 3 (Linux 6.2+); saboteur mutant children run with hazard guard + canary only (doctor warning preserved).

## Baseline state at pin (post D-ENV-1, EX-1 NOT applied to baselines)
- Full suite: 913 examples, 1 failure, exit 1, wall 41.93s, peak RSS 463384 KB (2026-10-24 06:47 IST) - sole red: spec/features/user_administration_spec.rb:39 banning (sent_emails 0 vs 1)
- With EX-1: 908 examples (dry-run count), suite expected green under saboteur's gate
