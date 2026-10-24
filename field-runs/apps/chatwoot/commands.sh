#!/bin/bash
# Chatwoot field-run commands, executed in order, on the sandbox (2 CPU / 1.9GB RAM, Ubuntu 22.04, no sudo).
# Recorded commands and grouped provisioning notes. Not a complete shell transcript.
# See REPRODUCE.md for helper placement and timing/resource limitations.
# Timestamps IST (Asia/Calcutta), 2026-10-23.
set -x

# --- toolchain provisioning (SETUP DEVIATION: documented flow assumes apt/sudo; sandbox has no sudo, no ruby, no services) ---
# Built from source under $HOME/local (no system changes):
#   openssl 3.0.16  : ./Configure --prefix=$HOME/local --openssldir=$HOME/local/ssl linux-x86_64 && make -j2 && make install_sw
#   libyaml 0.2.5   : ./configure --prefix=$HOME/local && make -j2 && make install
#   redis 7.2.5     : make -j2 && make PREFIX=$HOME/local install
#   postgresql 16.10: ./configure --prefix=$HOME/local/pgsql --without-readline --without-icu && make -j2 && make install
#   pgvector 0.8.0  : make PG_CONFIG=$HOME/local/pgsql/bin/pg_config && make ... install
#   pg_stat_statements, pg_trgm, pgcrypto built from contrib/ (pgcrypto with CPPFLAGS=-I$HOME/local/include SHLIB_LINK="-L$HOME/local/lib64 -lcrypto -Wl,-rpath,$HOME/local/lib64")
#   ruby 3.4.4      : ./configure --prefix=$HOME/local/ruby --with-openssl-dir=$HOME/local --with-libyaml-dir=$HOME/local --disable-install-doc && make -j2 && make install
#     (openssl ext rebuilt manually: cd ext/openssl && ruby extconf.rb --with-openssl-dir=$HOME/local && make && make install -- openssl had installed libs to lib64/, symlinks added into lib/)
#   node 24.13.0    : official nodejs.org linux-x64 tarball (matches .node-version); pnpm 10.2.0 via corepack (matches package.json packageManager)

# --- services ---
initdb -D ~/pgdata -U postgres --auth=trust --no-instructions -E UTF8 --locale=C.UTF-8   # 2nd initdb; 1st defaulted to SQL_ASCII, see findings
pg_ctl -D ~/pgdata -l ~/pgdata.log -o "-p 5432 -c listen_addresses=localhost -c shared_buffers=256MB -c fsync=off -c full_page_writes=off -c synchronous_commit=off" start
$HOME/local/bin/redis-server --daemonize yes --port 6379 --save '' --appendonly no --logfile ~/redis.log

# --- app source ---
# tarball fetch was replaced by real git (PR flow needs history):
git clone --filter=blob:none https://github.com/chatwoot/chatwoot.git chatwoot-git
cd chatwoot-git && git checkout 7fe41fe03731fc2f5b1841b84351386962d2fd05   # == develop HEAD at fetch time; PIN verified ancestor

# --- env file (.env, test) ---
# RAILS_ENV=test REDIS_URL=redis://localhost:6379 POSTGRES_HOST=localhost POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres
# POSTGRES_PASSWORD=(empty) POSTGRES_DATABASE=chatwoot_test SECRET_KEY_BASE=<fixed hex> ACTIVE_RECORD_ENCRYPTION_*=<fixed hex> FRONTEND_URL=http://localhost:3000

# --- CE scope strip, mirrors .github/workflows/run_foss_spec.yml "Strip enterprise code" at the pin ---
rm -rf enterprise spec/enterprise    # 349 enterprise specs excluded from CE scope; recorded exclusion

# --- deps ---
source ~/fieldruns/env.sh            # PATH/LD_LIBRARY_PATH for $HOME/local toolchain; RAILS_ENV=test
gem install bundler -v 2.5.16 --no-document   # BUNDLED WITH 2.5.16
bundle config set --local path vendor/bundle && bundle config set --local without 'development'
bundle install --jobs 2              # 356 installs, exit 0
pnpm i                               # node 24.13.0 + pnpm 10.2.0, done in 31.8s

# --- database (CI parity: db:create + db:schema:load) ---
bundle exec rake db:create db:schema:load   # db:create ok after UTF8 re-init; schema:load ok after contrib extensions installed; 110 tables

# --- smoke ---
bundle exec rspec spec/models/account_spec.rb --format progress   # 74 examples, 0 failures

# --- BASELINE (narrowed scope per user's "directories you'll use" allowance + 21:58 "faster" steer) ---
# scope: spec/models (64 files) + spec/services (201 files) = 265 of 665 CE spec files
# reason: 2-CPU/1.9GB sandbox cannot run 665 files serially within the 4h timebox; models+services cover
#         app/models + app/services, the core domain logic a mutation PR gate targets.
# attempt 1 (FAILED, exit 127): /usr/bin/time -v bundle exec rspec ... -> /usr/bin/time does not exist on this host; recorded, not rerun as-is
# actual executed (via helpers/run-baseline.sh, attached): bash time/dates for wall + a 2s ps-VmRSS process-tree sampler for peak RSS
~/fieldruns/run-baseline.sh   # = bundle exec rspec spec/models spec/services --format progress --format json --out ~/fieldruns/evidence/apps/chatwoot/logs/baseline-rspec.json
# additional baseline (PR-relevant specs outside models+services): via helpers/run-baseline-extra.sh
~/fieldruns/run-baseline-extra.sh  # = bundle exec rspec spec/mailboxes/imap/imap_mailbox_spec.rb spec/jobs/trigger_scheduled_items_job_spec.rb --format progress --format json --out .../baseline-extra-rspec.json
# NOTE on memory method: peak_rss_kb is a 2s-sampled sum of VmRSS over the rspec process tree only; excludes postgres/redis; may miss <2s spikes. NOT comparable with ru_maxrss-based numbers (e.g. the Lobsters run).
