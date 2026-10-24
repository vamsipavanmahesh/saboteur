#!/usr/bin/env bash
# pr_replay.sh <era_tree> <base_sha> <head_sha> <pr_url> <out_dir> - scoped noise replay.
# SAME era root/tree as that PR's whole map. Fail-closed pointer+key-binding check BEFORE replay.
# Bounded outer deadline (provisional OUTER, re-sized after fixed-pin doctor validation).
set -uo pipefail
exec 9>/home/sandbox/field-run/.serial.lock
flock -n 9 || { echo "SERIAL-LOCK-BUSY"; exit 23; }
TREE="$1"; BASE="$2"; HEAD="$3"; PRURL="$4"; OUT="$5"; mkdir -p "$OUT"
export PATH=/home/sandbox/ruby343/bin:$PATH PG_HOST=/tmp/pgsock PG_USERNAME=postgres RAILS_ENV=test
export BUNDLE_PATH=/home/sandbox/bundle MAKEFLAGS=-j1
OUTER="${OUTER:-2700}"
cd "$TREE" || exit 1
ACTUAL=$(git rev-parse HEAD)
[ "$ACTUAL" = "$HEAD" ] || { echo "ERA-TREE-MISMATCH $ACTUAL != $HEAD (ledger head)"; exit 16; }
git cat-file -e "$BASE^{commit}" && git cat-file -e "$HEAD^{commit}" || { echo "MISSING-REFS"; exit 14; }
git merge-base --is-ancestor "$BASE" "$HEAD" || { echo "BASE-NOT-ANCESTOR"; exit 15; }
# fail-closed: whole-map pointer must exist, be non-empty, and bind to coverage+inputs JSONs
PTR=.saboteur/whole-suite-map-v2
[ -s "$PTR" ] || { echo "POINTER-MISSING: whole map must complete in this tree first"; exit 19; }
KEY=$(tr -d '[:space:]' < "$PTR")
[ -n "$KEY" ] && [ -f ".saboteur/coverage-$KEY.json" ] && [ -f ".saboteur/inputs-$KEY.json" ] \
  || { echo "POINTER-BINDING-BROKEN key=$KEY"; exit 20; }
sha256sum "$PTR" ".saboteur/coverage-$KEY.json" ".saboteur/inputs-$KEY.json" > "$OUT/pointer-receipt-before.txt"
export KIND=pr BASE_SHA="$BASE" HEAD_SHA="$HEAD" PR_URL="$PRURL" LOG_FILE="$OUT/replay.log"
timeout --signal=INT --kill-after=30 "$OUTER" \
  python3 /home/sandbox/field-run/bin/measure.py "$OUT/measurement.json" \
  bundle exec saboteur pr --since "$BASE" --jobs 1 --json "$OUT/report.json" --html "$OUT/report.html"
RC=$?
sha256sum "$PTR" ".saboteur/coverage-$KEY.json" ".saboteur/inputs-$KEY.json" > "$OUT/pointer-receipt-after.txt"
echo "exit=$RC" >> "$OUT/pointer-receipt-after.txt"
exit $RC
