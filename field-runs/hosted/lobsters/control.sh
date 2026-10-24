#!/usr/bin/env bash
# Unchanged-suite control on the instrumented tree: fresh database, defined seed, no exclusions.
source "$(dirname "$0")/lib.sh"
cd "$APP_DIR"; L="$OUT/control.log"
stamp "CONTROL_START pr=$PR side=$SIDE seed=$SEED" | tee -a "$L"
measured "$OUT/db-reset-meta.json" 600 bundle exec rails db:drop db:create db:schema:load >> "$L" 2>&1 || { echo "CONTROL_BLOCK: db reset failed (see db-reset-meta.json)" | tee -a "$L"; exit 1; }
rc=0; measured "$OUT/control-meta.json" 5400 bundle exec rspec --seed "$SEED" --format progress --format json --out "$OUT/control-rspec.json" >> "$L" 2>&1 || rc=$?
stamp "CONTROL_END exit=$rc" | tee -a "$L"
exit "$rc"
