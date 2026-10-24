#!/usr/bin/env bash
# bug_replay.sh <intro_tree> <intro_base_sha> <intro_head_sha> <pr_url> <out_dir> -
# introducing-PR replay at its own era, tests as then. Same fail-closed + bounded rules.
set -uo pipefail
exec 9>/home/sandbox/field-run/.serial.lock
flock -n 9 || { echo "SERIAL-LOCK-BUSY"; exit 23; }
TREE="$1"; BASE="$2"; HEAD="$3"; PRURL="$4"; OUT="$5"; mkdir -p "$OUT"
export PATH=/home/sandbox/ruby343/bin:$PATH PG_HOST=/tmp/pgsock PG_USERNAME=postgres RAILS_ENV=test
export BUNDLE_PATH=/home/sandbox/bundle MAKEFLAGS=-j1
OUTER="${OUTER:-2700}"
cd "$TREE" || exit 1
ACTUAL=$(git rev-parse HEAD)
[ "$ACTUAL" = "$HEAD" ] || { echo "TREE-HEAD-MISMATCH $ACTUAL != $HEAD"; exit 16; }
git merge-base --is-ancestor "$BASE" "$HEAD" || { echo "BASE-NOT-ANCESTOR"; exit 15; }
export KIND=bug-pr BASE_SHA="$BASE" HEAD_SHA="$HEAD" PR_URL="$PRURL" LOG_FILE="$OUT/replay.log"
timeout --signal=INT --kill-after=30 "$OUTER" \
  python3 /home/sandbox/field-run/bin/measure.py "$OUT/measurement.json" \
  bundle exec saboteur pr --since "$BASE" --jobs 1 --json "$OUT/report.json" --html "$OUT/report.html"
exit $?
