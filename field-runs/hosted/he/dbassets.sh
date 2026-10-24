#!/usr/bin/env bash
# dbassets.sh: fresh test DB and assets for the tree currently at the app root. Environment steps, not exclusions.
source "$(dirname "$0")/lib.sh"; cd "$APP_ROOT"; L="$OUT/dbassets.log"
stamp "DBASSETS_START head=$(git rev-parse HEAD)" | tee -a "$L"
pg_isready -h "$PG_HOST" -p 5432 | tee -a "$L" || { echo "DB_BLOCK: postgres not ready" | tee -a "$L"; exit 1; }
measured "$OUT/db-reset-meta.json" 900 bash -c 'bin/rails db:drop db:create db:schema:load' >> "$L" 2>&1 || { echo "DB_BLOCK: db reset failed (db-reset-meta.json)" | tee -a "$L"; exit 1; }
[ ! -f package.json ] && [ ! -f yarn.lock ] && [ ! -f package-lock.json ] || { echo "ASSETS_BLOCK: this tree has a JS package manager file; not covered by this recipe" | tee -a "$L"; exit 1; }
{ for c in $(docker ps -q 2>/dev/null); do docker inspect --format '{{.Config.Image}} {{.Image}}' "$c"; done; } 2>&1 | tee "$OUT/service-image-identity.txt" | tee -a "$L" || true
# structured, authenticated, bounded SQL (libpq reads PGPASSWORD; Rails reads PG_PASSWORD); the secret is never printed
psqlq() { timeout 30 env PGPASSWORD="$PG_PASSWORD" psql --no-password -v ON_ERROR_STOP=1 -h "$PG_HOST" -U "$PG_USERNAME" -d "$1" -AtF '|' -c "$2"; }
{ psqlq postgres "select version()"; psqlq diaper_test "select current_setting('server_version_num'), pg_encoding_to_char(encoding), datcollate, datctype from pg_database where datname = current_database()"; } > "$OUT/postgres-identity.txt" 2>"$OUT/postgres-identity.err" || { echo "DB_BLOCK: authenticated SQL identity query failed (postgres-identity.err)" | tee -a "$L"; exit 1; }
cat "$OUT/postgres-identity.txt" | tee -a "$L"
# historical study server: PostgreSQL 14.24, initdb -E UTF8 --locale=C. Hosted is a NEW environment (container image); assert the parsed fields, claim no parity.
[ "$(sed -n 2p "$OUT/postgres-identity.txt")" = "140024|UTF8|C|C" ] || { echo "DB_BLOCK: expected server_version_num|encoding|collate|ctype 140024|UTF8|C|C" | tee -a "$L"; exit 1; }
measured "$OUT/assets-meta.json" 1800 bin/rails assets:precompile >> "$L" 2>&1 || { echo "ASSETS_BLOCK: assets:precompile failed (assets-meta.json)" | tee -a "$L"; exit 1; }
stamp "DBASSETS_DONE" | tee -a "$L"
