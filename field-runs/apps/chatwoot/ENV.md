# Chatwoot environment (apps/chatwoot)

## App
- repo: https://github.com/chatwoot/chatwoot
- pinned SHA: 7fe41fe03731fc2f5b1841b84351386962d2fd05 (was develop HEAD at fetch 2026-10-23 ~21:43 IST; verified in-history)
- Rails 7.2.3.1, RSpec; .ruby-version 3.4.4; .node-version 24.13.0; packageManager pnpm@10.2.0
- size at pin: 2957 tracked Ruby files, 1014 *_spec.rb (665 CE after stripping spec/enterprise per FOSS CI)

## Host (sandbox, not the user's machine)
- Ubuntu 22.04.5 LTS x86_64, 2 CPU, 1.9 GB RAM (1.7 GB available), 20 GB free disk, NO sudo
- nothing preinstalled for the app: no ruby, no postgres server headers, no redis-server, no pgvector

## Toolchain (all built/installed under $HOME, no system changes) - SETUP DEVIATION from docs (docs assume apt/sudo)
- ruby 3.4.4 from source (cache.ruby-lang.org tarball), openssl 3.0.16 + libyaml 0.2.5 from source
- postgresql 16.10 from source + pgvector 0.8.0 + contrib pg_stat_statements/pg_trgm/pgcrypto (pgcrypto linked to openssl 3.0.16)
- redis 7.2.5 from source
- node 24.13.0 official tarball, pnpm 10.2.0 via corepack
- bundler 2.5.16 (BUNDLED WITH), 356 gems installed via bundle install, pnpm i ok

## Services (running on localhost)
- postgres 16.10 port 5432, db chatwoot_test, schema loaded (110 tables), extensions: vector 0.8.0, pg_stat_statements, pg_trgm, pgcrypto, plpgsql
- redis 7.2.5 port 6379

## Deviations / friction recorded (details in findings.md)
1. Docs' apt/sudo install path impossible (no sudo): whole toolchain source-built.
2. First initdb defaulted to SQL_ASCII (no locale env) -> db:create failed; re-init with -E UTF8 --locale=C.UTF-8.
3. schema.rb requires pg_stat_statements + pgcrypto + pg_trgm; source postgres needed contrib modules built (pgcrypto needed openssl headers/rpath fix).
4. ruby openssl ext initially failed (openssl installed libs to lib64/, ruby extconf looked in lib/); fixed via symlinks + ext rebuild.

## saboteur
- version: NOT RUN yet. 0.13.0 not released; versioned saboteur measurements held until main sends verified 0.13.0 SHA.
