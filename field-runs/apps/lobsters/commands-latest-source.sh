#!/usr/bin/env bash
# Lobsters field-run: EXACT commands as executed, in order, with the helpers they need.
# Helpers (attached alongside this file): env.sh (all env vars), runmeasured.py (wall/RSS wrapper).
# App: https://github.com/lobsters/lobsters  Pinned SHA: 407536444934ac7d78f4ce1c18f228e3891a8663
# Machine: Ubuntu 22.04.5 sandbox container, 2 CPU, 1.9GB RAM, NO sudo. All times IST (+0530).
# Anything not in this file did not happen. Deviations from CONTRIBUTING.md are marked [DEVIATION].

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
grep -n 'CGI.parse' extras/github.rb                     # -> line 21
sed -n '36,50p' spec/features/user_administration_spec.rb # failing expectation = line 50 sent_emails.size eq 1

# --- 9. PR head-tree pre-verification (no saboteur; speed steer: only each PR's own spec files) ---
# KEY: every PR head tree pins Ruby 4.0.0 in its own .ruby-version -> separate prebuilt Ruby, per-tree GEM_HOME:
cd ~/field-runs/ruby
curl -sL -o ruby-4.0.0.tar.gz https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.0/ruby-4.0.0-ubuntu-22.04-x64.tar.gz
tar xzf ruby-4.0.0.tar.gz && mv x64 ruby-4.0.0
cd ruby-4.0.0/bin && for f in *; do if [ "$(head -c2 "$f")" = "#!" ]; then sed -i '1s|.*|#!/usr/bin/env ruby|' "$f"; fi; done
sed 's|ruby-4.0.9|ruby-4.0.0|g' ~/field-runs/env.sh > ~/field-runs/env400.sh
# [DEVIATION] pr2053 (July-9 MySQL/trilogy era) additionally needed OpenSSL headers:
cd ~/field-runs/pkgs && apt-get download libssl-dev && for d in libssl-dev*.deb; do dpkg-deb -x "$d" root; done
# CPATH extended with the multiarch include dir (openssl/opensslconf.h) in env.sh/env400.sh.
# Per tree (example pr2231; identical pattern for pr2204 pr2156 pr2090 pr2143), serially:
source ~/field-runs/env400.sh
cd ~/field-runs/lobsters && git worktree add --detach ~/field-runs/pr-trees/pr2231 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8
cd ~/field-runs/pr-trees/pr2231
bundle config set --local build.psych "--with-libyaml-include=$HOME/field-runs/pkgs/root/usr/include --with-libyaml-lib=$HOME/field-runs/pkgs/root/usr/lib/x86_64-linux-gnu"
bundle install && bin/setup
python3 ~/field-runs/runmeasured.py $HOME/field-runs/saboteur-field-runs/apps/lobsters/reports/pr2231-head-specs/measurement-raw.json -- \
  bundle exec rspec spec/models/comment_spec.rb spec/requests/comments_spec.rb spec/mailers/email_reply_mailer_spec.rb \
  --format progress --format json --out $HOME/field-runs/saboteur-field-runs/apps/lobsters/logs/pr2231-head-specs.json
# pr2204: spec/models/story_spec.rb | pr2156: spec/controllers/settings_controller_spec.rb
# pr2090: spec/controllers/home_controller_spec.rb spec/routing/home_spec.rb | pr2143: spec/models/story_spec.rb
# pr2053: documented bin/setup FAILS at db:create - trilogy_connect 127.0.0.1:3306 refused (F-ENV-2);
#         demoted to spare, #2143 substituted (prs/selected_prs.json).

# --- 10. PR BASE-tree control checks (no saboteur; pre-mutation controls) ---
# Same pattern as section 9 but worktrees at base_sha (dir pr-trees/pr<N>-base), Ruby 4.0.0 for all 5 bases.
# pr2231 base 372345a2cc: 3 spec files -> 40 ex 0 fail
# pr2204 base 8f1b50061e: spec/models/story_spec.rb -> 76 ex 0 fail
# pr2156 base 9a773eac0b: spec/controllers/settings_controller_spec.rb -> RAW LoadError, file added by PR (narrow N/A, 0 examples)
# pr2143 base e72cf85f04: spec/models/story_spec.rb -> 75 ex 0 fail
# pr2090 base 81ba649e (identical SHA to pr2143 HEAD): reused pr2143 worktree, ran spec/controllers/home_controller_spec.rb spec/routing/home_spec.rb -> 32 ex 0 fail
