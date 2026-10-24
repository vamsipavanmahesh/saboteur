#!/usr/bin/env bash
# Lobsters field-run replay recipe with recorded commands and setup notes.
# Provisioning is grouped for replay, not a literal transcript of attempt chronology.
# Actual setup attempts and their order are preserved in logs/bin-setup.log.
# Helpers (attached alongside this file): env.sh (all env vars), runmeasured.py (wall/RSS wrapper).
# App: https://github.com/lobsters/lobsters  Pinned SHA: 407536444934ac7d78f4ce1c18f228e3891a8663
# Machine: Ubuntu 22.04.5 sandbox container, 2 CPU, 1.9GB RAM, NO sudo. All times IST (+0530).
# Deviations from CONTRIBUTING.md are marked [DEVIATION].
# See REPRODUCE.md for helper placement, output paths and reproduction limits.

# --- 0. helpers ---
# env.sh          - exports RUBY_HOME/LD_LIBRARY_PATH/RUBYLIB/GEM_HOME/GEM_PATH/PATH/PKG_CONFIG_PATH/CPATH/LIBRARY_PATH
# runmeasured.py  - python3 wrapper: records started_at/ended_at/wall_seconds/exit_code/peak_rss_kb to JSON

# --- 1. fetch app at pin ---
mkdir -p ~/field-runs && cd ~/field-runs
git clone --filter=blob:none --no-checkout https://github.com/lobsters/lobsters.git
cd lobsters
git fetch --depth 1 origin 407536444934ac7d78f4ce1c18f228e3891a8663
git checkout -q 407536444934ac7d78f4ce1c18f228e3891a8663
# verified: git log -1 -> 407536444934ac7d78f4ce1c18f228e3891a8663 2026-10-23 10:06:27 -0500
# later, for PR history only: git fetch --depth 400 origin main

# --- 2. Ruby 4.0.9 (doc step: install .ruby-version) [DEVIATION: no sudo/apt; official prebuilt] ---
cd ~/field-runs
curl -sL -o ruby-4.0.9.tar.gz https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.9/ruby-4.0.9-ubuntu-22.04-x64.tar.gz
mkdir -p ruby && cd ruby && tar xzf ../ruby-4.0.9.tar.gz && mv x64 ruby-4.0.9
# tarball shebangs point at a GitHub-hosted-toolcache path that does not exist here; repointed TEXT scripts only:
cd ruby-4.0.9/bin && for f in *; do if [ "$(head -c2 "$f")" = "#!" ]; then sed -i '1s|.*|#!/usr/bin/env ruby|' "$f"; fi; done
# verified: ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux]; OpenSSL 3.0.2

# --- 3. libvips (doc step: sudo apt install libvips) [DEVIATION: no sudo; jammy 8.12.1 then REJECTED by Rails 8.1] ---
mkdir -p ~/field-runs/pkgs
cd ~/field-runs/pkgs
apt-get download libvips42 libcfitsio9 libcgif0 libgsf-1-114 libmatio11 libopenslide0 libhdf5-103 libhdf5-103-1 libsz2 libaec0 libyaml-dev libyaml-0-2
for d in *.deb; do dpkg-deb -x "$d" root; done   # local extract into pkgs/root (jammy libvips 8.12.1)
# bin/setup attempt 2 PROVED jammy 8.12.1 unusable (Rails 8.1 needs >=8.13) -> F-ENV-1.
# Resolution actually used: sharp's official prebuilt libvips 8.18.7 (single .so with deps statically linked):
curl -sL -o sharp-libvips.tgz https://registry.npmjs.org/@img/sharp-libvips-linux-x64/-/sharp-libvips-linux-x64-1.3.4.tgz
tar xzf sharp-libvips.tgz   # package/lib/libvips-cpp.so.8.18.7
mkdir -p vips818/lib && ln -sf ~/field-runs/pkgs/package/lib/libvips-cpp.so.8.18.7 ~/field-runs/pkgs/vips818/lib/libvips.so.42
# verified loaded via ruby FFI: vips_version(0..2) -> 8.18.7

# --- 4. psych native build needs libyaml headers (bin/setup attempt 1 failure) [DEVIATION: local -dev extract] ---
cd ~/field-runs/lobsters
source ~/field-runs/env.sh
bundle config set --local build.psych "--with-libyaml-include=$HOME/field-runs/pkgs/root/usr/include --with-libyaml-lib=$HOME/field-runs/pkgs/root/usr/lib/x86_64-linux-gnu"
# (app's own .bundle/config sqlite3 flags preserved untouched)

# --- 5. documented setup ---
source ~/field-runs/env.sh
cd ~/field-runs/lobsters
bin/setup   # attempt 1: FAIL psych yaml.h (21:46:37) | attempt 2: FAIL libvips>=8.13 (21:47:35) | attempt 3: EXIT 0 (21:50:59)
# full log: logs/bin-setup.log ; created db/{development,test}/*.sqlite3

# --- 6. baseline (whole suite, actual, preserved) ---
python3 ~/field-runs/runmeasured.py $HOME/field-runs/saboteur-field-runs/apps/lobsters/reports/baseline/measurement-raw.json -- \
  bundle exec rspec --format progress --format json --out $HOME/field-runs/saboteur-field-runs/apps/lobsters/logs/baseline-rspec.json
# 2026-10-23T21:54:30+0530 -> 21:55:06+0530, wall 35.345s, exit 1, peak_rss_kb 454056
# 913 examples, 2 failures, 0 pending. stdout+stderr: logs/baseline-rspec.log

# --- 7. failure rechecks (2 isolated reruns of the 2 failing files) ---
for i in 1 2; do bundle exec rspec spec/extras/github_spec.rb spec/features/user_administration_spec.rb; done
# both files failed in both reruns; log: logs/baseline-failures-recheck.log

# --- 8. factual cause checks (read-only) ---
ruby -e 'require "cgi"; puts CGI.respond_to?(:parse)'   # -> false (cgi 0.5.1 in Ruby 4.0.9)
# CORRECTION 2026-10-24: the false above came from the core-dir RUBYLIB ordering loading Ruby's cgi stub, not from cgi 0.5.1 (which defines CGI.parse, core.rb:396). See reports/cgi-loadpath-recovery/RECOVERY.md.
grep -n 'CGI.parse' extras/github.rb                     # -> line 21
sed -n '36,50p' spec/features/user_administration_spec.rb # failing expectation = line 50 sent_emails.size eq 1
