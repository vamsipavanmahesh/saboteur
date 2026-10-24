#!/bin/bash
# Full toolchain provisioning, exactly as executed 2026-10-23 21:40-21:55 IST (all succeeded as run in this order, fixes included).
# Host: Ubuntu 22.04 x86_64, 2 CPU, 1.9GB RAM, no sudo. Everything under $HOME; no system changes.
set -e
mkdir -p ~/src ~/local
cd ~/src
# sources
curl -sLO https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.4.tar.gz
curl -sLO https://ftp.postgresql.org/pub/source/v16.10/postgresql-16.10.tar.gz
curl -sL -o pgvector-0.8.0.tar.gz https://github.com/pgvector/pgvector/archive/refs/tags/v0.8.0.tar.gz
curl -sLO https://github.com/openssl/openssl/releases/download/openssl-3.0.16/openssl-3.0.16.tar.gz
curl -sLO https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz
curl -sLO https://download.redis.io/releases/redis-7.2.5.tar.gz
curl -sLO https://nodejs.org/dist/v24.13.0/node-v24.13.0-linux-x64.tar.gz
for f in *.tar.gz; do tar xzf "$f"; done

# openssl 3.0.16 (installs libs to $HOME/local/lib64 on linux-x86_64)
cd ~/src/openssl-3.0.16
./Configure --prefix=$HOME/local --openssldir=$HOME/local/ssl linux-x86_64
make -j2
make install_sw
# ruby extconf only looks in <prefix>/lib - symlink the lib64 artifacts in
ln -sf $HOME/local/lib64/libssl* $HOME/local/lib64/libcrypto* $HOME/local/lib/

# libyaml 0.2.5
cd ~/src/yaml-0.2.5 && ./configure --prefix=$HOME/local && make -j2 && make install

# redis 7.2.5
cd ~/src/redis-7.2.5 && make -j2 && make PREFIX=$HOME/local install

# postgresql 16.10
cd ~/src/postgresql-16.10
./configure --prefix=$HOME/local/pgsql --without-readline --without-icu
make -j2 && make install

# pgvector 0.8.0
cd ~/src/pgvector-0.8.0
make PG_CONFIG=$HOME/local/pgsql/bin/pg_config
make PG_CONFIG=$HOME/local/pgsql/bin/pg_config install

# contrib modules required by chatwoot db/schema.rb
for m in pg_stat_statements pg_trgm; do
  (cd ~/src/postgresql-16.10/contrib/$m && make PG_CONFIG=$HOME/local/pgsql/bin/pg_config && make PG_CONFIG=$HOME/local/pgsql/bin/pg_config install)
done
# pgcrypto needs openssl headers + explicit link (plain build leaves undefined EVP symbols)
cd ~/src/postgresql-16.10/contrib/pgcrypto
make PG_CONFIG=$HOME/local/pgsql/bin/pg_config CPPFLAGS="-I$HOME/local/include" SHLIB_LINK="-L$HOME/local/lib64 -lcrypto -Wl,-rpath,$HOME/local/lib64"
make PG_CONFIG=$HOME/local/pgsql/bin/pg_config install

# ruby 3.4.4 (matches chatwoot .ruby-version)
cd ~/src/ruby-3.4.4
./configure --prefix=$HOME/local/ruby --with-openssl-dir=$HOME/local --with-libyaml-dir=$HOME/local --disable-install-doc
make -j2 && make install
# openssl ext is skipped on first pass (probes before lib64 symlinks); build it explicitly
cd ~/src/ruby-3.4.4/ext/openssl
~/local/ruby/bin/ruby extconf.rb --with-openssl-dir=$HOME/local
make -j2 && make install
~/local/ruby/bin/ruby -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION'   # verify

# node + pnpm (match .node-version 24.13.0 and packageManager pnpm@10.2.0)
export PATH=$HOME/src/node-v24.13.0-linux-x64/bin:$PATH
corepack enable && corepack prepare pnpm@10.2.0 --activate

# services
export PATH=$HOME/local/pgsql/bin:$HOME/local/bin:$PATH
# NOTE: initdb MUST set UTF8 explicitly; default locale in a bare env yields SQL_ASCII and rails db:create fails
initdb -D ~/pgdata -U postgres --auth=trust --no-instructions -E UTF8 --locale=C.UTF-8
pg_ctl -D ~/pgdata -l ~/pgdata.log -o "-p 5432 -c listen_addresses=localhost -c shared_buffers=256MB -c fsync=off -c full_page_writes=off -c synchronous_commit=off" start
$HOME/local/bin/redis-server --daemonize yes --port 6379 --save '' --appendonly no --logfile ~/redis.log
