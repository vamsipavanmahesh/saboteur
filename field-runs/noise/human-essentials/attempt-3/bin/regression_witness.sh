#!/usr/bin/env bash
# regression_witness.sh <tree> <out_dir> <spec_file...> - run specs, record ACTUAL rc.
# FAIL-before (nonzero) is a legitimate witness: receipt records actual rc, caller interprets.
set -uo pipefail
exec 9>/home/sandbox/field-run/.serial.lock
flock -n 9 || { echo "SERIAL-LOCK-BUSY"; exit 23; }
TREE="$1"; shift; OUT="$1"; shift; mkdir -p "$OUT"
export PATH=/home/sandbox/ruby343/bin:$PATH PG_HOST=/tmp/pgsock PG_USERNAME=postgres RAILS_ENV=test
export BUNDLE_PATH=/home/sandbox/bundle MAKEFLAGS=-j1
OUTER="${OUTER:-3600}"
cd "$TREE" || exit 1
git rev-parse HEAD > "$OUT/witness-tree-sha.txt"
export KIND=witness LOG_FILE="$OUT/witness.log"
timeout --signal=INT --kill-after=30 "$OUTER" \
  python3 /home/sandbox/field-run/bin/measure.py "$OUT/measurement.json" \
  bundle exec rspec "$@" --format progress --format json --out "$OUT/rspec.json"
RC=$?
echo "exit=$RC" > "$OUT/witness-receipt.txt"
exit $RC
