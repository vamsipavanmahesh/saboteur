#!/usr/bin/env bash
# map.sh <era S1..S4>: whole-suite map at the era snapshot SHA, stopped at a validated boundary (producer only; no replay here).
source "$(dirname "$0")/lib.sh"
ERA=${1:?era}; SHA=$(awk -v e="$ERA" '$3==e {print $4; exit}' "$RECIPE_DIR/eras.env"); [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "MAP_BLOCK: unknown era"; exit 1; }
L="$OUT/map.log"
bash "$RECIPE_DIR/prep.sh" "$SHA" || { echo "MAP_BLOCK: prep failed" | tee -a "$L"; exit 1; }
require_doctor | tee -a "$L"; [ "${PIPESTATUS[0]}" = 0 ] || { echo "MAP_BLOCK: no green doctor for this recipe and identity" | tee -a "$L"; exit 1; }
bash "$RECIPE_DIR/dbassets.sh" || { echo "MAP_BLOCK: db/assets failed" | tee -a "$L"; exit 1; }
cd "$APP_ROOT"; git rev-parse HEAD > "$OUT/map-head-sha.txt"; echo "$ERA" > "$OUT/map-era.txt"
{ echo "METHOD: whole-suite map at the era snapshot, native command, boundary-stopped; producer and consumer share root $APP_ROOT"
  echo "SEED: not set by this recipe; the native default applies and is recorded in inputs JSON (seed) and the log. This differs from the Lobsters seed-3 flow and is not homogenized with it."; echo "CMD: saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose --json map-report.json"; } > "$OUT/METHOD.txt"
rm -rf .saboteur
WD=$(( $(left_s) - 3600 )); [ "$WD" -gt 3600 ] || { echo "MAP_BLOCK: not enough job time left for the map (left=$(left_s)s)" | tee -a "$L"; exit 1; }
ASTART=$(date +%s); stamp "MAP_START attempt_start_epoch=$ASTART watch_deadline_s=$WD" | tee -a "$L"
rc=0
python3 "$RECIPE_DIR/measure3.py" --meta "$OUT/map-meta.json" --cwd "$APP_ROOT" --watch-dir "$APP_ROOT/.saboteur" --attempt-start "$ASTART" \
  --expect-root "$APP_ROOT" --expect-seed 1 --expect-identity-file "$OUT/deps/expected-identity.json" --watch-deadline "$WD" --timeout $(( WD + 300 )) -- \
  bundle exec saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose --json "$OUT/map-report.json" > "$OUT/map.log.raw" 2>&1 || rc=$?
stamp "MAP_END exit=$rc" | tee -a "$L"
copy_cache_known map | tee -a "$L"
state=$(jq -r '.boundary.state' "$OUT/map-meta.json")
{ echo "MAP_EXIT=$rc BOUNDARY_STATE=$state (130 with state sent is a deliberate stop at a validated boundary, never a suite pass or row admission)"
  echo "BASELINE_AND_MAP_LOG_LINES (recorded observations only):"; { grep -E 'baseline|coverage map|tests in|subjects' "$OUT/map.log.raw" || true; } | tail -8; } | tee "$OUT/MAP-RECEIPT.txt" | tee -a "$L"
[ "$rc" = 130 ] && [ "$state" = sent ] || { echo "MAP_BLOCK: no validated boundary stop (exit=$rc state=$state)" | tee -a "$L"; exit 1; }
KEY=$(tr -d '[:space:]' < .saboteur/whole-suite-map-v2)
[ "$KEY" = "$(jq -r '.boundary.pointer_key' "$OUT/map-meta.json")" ] || { echo "MAP_BLOCK: pointer changed after validation" | tee -a "$L"; exit 1; }
mkdir -p "$OUT/triple"
for f in "coverage-$KEY.json" "inputs-$KEY.json" whole-suite-map-v2; do
  [ "$(sha256sum ".saboteur/$f" | cut -d' ' -f1)" = "$(jq -r --arg f "$f" '.boundary.sha256[$f]' "$OUT/map-meta.json")" ] || { echo "MAP_BLOCK: $f differs from validated bytes" | tee -a "$L"; exit 1; }
  cp -p ".saboteur/$f" "$OUT/triple/$f"
done
( cd "$OUT/triple" && sha256sum * ) | tee "$OUT/TRIPLE.sha256" | tee -a "$L"
echo "MAP_TEST_COUNT $(jq '.tests | length' ".saboteur/coverage-$KEY.json")" | tee -a "$OUT/MAP-RECEIPT.txt"
echo "TRIPLE_QUALIFIED_AS_ARTIFACT key=$KEY snapshot=$SHA era=$ERA root=$APP_ROOT (not a study row)" | tee -a "$L"
