#!/usr/bin/env bash
# whole_map.sh <era_tree> <out_dir> - HE-adapted from approved run-map3 reference (2026-10-24).
# Per-era whole-suite map: owned-PID watch4 boundary observer, no generic pkill, bounded outer
# deadline, artifacts fail-closed, map count from JSON. pipefail added (reference lacked it).
set -uo pipefail
exec 9>/home/sandbox/field-run/.serial.lock
flock -n 9 || { echo "SERIAL-LOCK-BUSY"; exit 23; }
TREE="$1"; OUT="$2"; mkdir -p "$OUT"
export PATH=/home/sandbox/ruby343/bin:$PATH PG_HOST=/tmp/pgsock PG_USERNAME=postgres RAILS_ENV=test
export BUNDLE_PATH=/home/sandbox/bundle MAKEFLAGS=-j1
OUTER="${OUTER:-2700}"   # provisional; re-sized from fixed-pin doctor validation
cd "$TREE" || exit 1
HEAD_NOW=$(git rev-parse HEAD); echo "$HEAD_NOW" > "$OUT/map-head-sha.txt"
export KIND=whole-map LOG_FILE="$OUT/whole-map.log"
ASTART=$(date +%s)
echo "$ASTART" > "$OUT/attempt-start-epoch.txt"
timeout --signal=INT --kill-after=30 "$OUTER" \
  python3 /home/sandbox/field-run/bin/measure.py "$OUT/measurement.whole-map.json" \
  bundle exec saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose \
  --json "$OUT/map-report.json" &
SABPID=$!
TSTART=$(awk '{print $22}' /proc/$SABPID/stat)
cp map-boundary-watch4.sh "$OUT/watch4-$SABPID.sh" && chmod +x "$OUT/watch4-$SABPID.sh"   # immutable per-attempt copy
"$OUT/watch4-$SABPID.sh" "$TREE" "$SABPID" "$TSTART" "$ASTART" >> "$LOG_FILE" 2>&1 &
WATCHER=$!
echo "MAP_START sabpid=$SABPID start_ticks=$TSTART watcher=$WATCHER attempt_start=$ASTART" >> "$LOG_FILE"
wait $SABPID; RC=$?
kill $WATCHER 2>/dev/null
{ echo "exit=$RC (130 with MAP_BOUNDARY_SIGINT_SENT = deliberate boundary stop, not PASS)"
  echo "head=$HEAD_NOW"
  stat -c '%n %y %s' .saboteur/coverage-*.json .saboteur/inputs-*.json .saboteur/whole-suite-map-v2 2>/dev/null
} > "$OUT/WHOLE-MAP-RECEIPT.txt"
cov=$(ls .saboteur/coverage-*.json 2>/dev/null | head -1)
if [ -n "$cov" ] && [ -f .saboteur/whole-suite-map-v2 ]; then
  ckey=$(basename "$cov" .json); ckey=${ckey#coverage-}
  inp=.saboteur/inputs-$ckey.json
  ptr=$(tr -d '[:space:]' < .saboteur/whole-suite-map-v2)
  { echo "MAP_DIGEST $(sha256sum "$cov")"
    echo "MAP_TEST_COUNT $(python3 -c "import json;m=json.load(open('$cov'));print(len(m.get('tests',[])))" 2>&1)"
    echo "MAP_POINTER_KEY $ptr"
    echo "MAP_KEY_BINDING $([ "$ptr" = "$ckey" ] && [ -f "$inp" ] && echo OK || echo BROKEN)"
  } >> "$OUT/WHOLE-MAP-RECEIPT.txt"
  if ! cp .saboteur/coverage-*.json .saboteur/inputs-*.json .saboteur/whole-suite-map-v2 "$OUT/"; then
    echo "ARTIFACT-COPY-FAILED: PARTIAL - source preserved in $TREE/.saboteur; map NOT qualified" >> "$OUT/WHOLE-MAP-RECEIPT.txt"
    exit 24
  fi
else
  echo "MAP_CACHE_INCOMPLETE (baseline red or build failed; see log)" >> "$OUT/WHOLE-MAP-RECEIPT.txt"
  exit 25
fi
exit $RC
