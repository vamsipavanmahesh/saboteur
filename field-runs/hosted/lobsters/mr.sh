#!/usr/bin/env bash
# Head tree only. Whole-suite map stopped at a verified map boundary, then the diff-mode replay vs the base commit.
# Called by full.sh after the admission gate.
source "$(dirname "$0")/lib.sh"
[ "$SIDE" = head ] || { echo "MR_BLOCK: head tree only"; exit 1; }
cd "$APP_DIR"; BASE=$(base_sha); L="$OUT/mr.log"
# declared method and scope
{ echo "METHOD: whole-suite map on the HEAD tree, then replay of the PR against its base on the same tree and path (new-environment hosted run)."
  echo "MAP: saboteur run --all --verbose --jobs 1 --no-cache --seed $SEED (default baseline passes), stopped at a verified map boundary, not a full mutation run."
  echo "REPLAY: saboteur run --since $BASE --baseline-passes 1 --max-duration 10m --jobs 1 --verbose --seed $SEED"
  echo "SCOPE: config include is app/**/*.rb (4 base-class excludes). Changed Ruby files outside it are listed in changed-files.txt as out of scope, not measured."
} | tee "$OUT/METHOD.txt" >> "$L"
git diff --name-only "$BASE" HEAD > "$OUT/changed-files.txt"
awk '/\.rb$/ { if ($0 ~ /^app\//) print "IN_SCOPE " $0; else print "OUT_OF_SCOPE " $0 }' "$OUT/changed-files.txt" > "$OUT/changed-ruby-scope.txt"
cat "$OUT/changed-ruby-scope.txt" | tee -a "$L"
# --- MAP ---
measured "$OUT/db-reset-map-meta.json" 600 bundle exec rails db:drop db:create db:schema:load >> "$L" 2>&1 || { echo "MR_BLOCK: db reset failed" | tee -a "$L"; exit 1; }
rm -rf .saboteur
WD=$(( $(left_s) - 3600 )); [ "$WD" -gt 600 ] || { echo "MR_BLOCK: not enough job time left for the map (left=$(left_s)s)" | tee -a "$L"; exit 1; }
[ "$WD" -le 5400 ] || WD=5400
ASTART=$(date +%s)
stamp "MAP_START attempt_start_epoch=$ASTART watch_deadline_s=$WD" | tee -a "$L"
rc=0
python3 "$RECIPE_DIR/measure3.py" --meta "$OUT/map-meta.json" --cwd "$APP_DIR" --watch-dir "$APP_DIR/.saboteur" --attempt-start "$ASTART" --expect-root "$(realpath "$APP_DIR")" --expect-seed "$SEED" --expect-identity-file "$OUT/deps/expected-identity.json" --watch-deadline "$WD" --timeout $(( WD + 300 )) -- \
  bundle exec saboteur run --all --verbose --jobs 1 --no-cache --seed "$SEED" > "$OUT/map.log" 2>&1 || rc=$?
stamp "MAP_END exit=$rc" | tee -a "$L"
mkdir -p "$OUT/map-artifacts"; cp -r .saboteur/. "$OUT/map-artifacts/" 2>/dev/null || true
state=$(jq -r '.boundary.state' "$OUT/map-meta.json")
{ echo "MAP_EXIT=$rc BOUNDARY_STATE=$state"
  echo "BASELINE_LINES: $(grep -c -E 'baseline check [12]' "$OUT/map.log")"; { grep -E 'baseline check|tests in coverage map|subjects,' "$OUT/map.log" || true; } | tail -6
  echo "MUTATION_STARTED_BEFORE_STOP: $(grep -c -E '^\.|^[.STE]+ +[0-9]+/[0-9]+' "$OUT/map.log") progress lines"
} | tee "$OUT/MAP-RECEIPT.txt" | tee -a "$L"
[ "$rc" = 130 ] && [ "$state" = sent ] || { echo "MR_BLOCK: map did not end at a verified boundary stop (exit=$rc state=$state); not a pass" | tee -a "$L"; exit 1; }
KEY=$(tr -d '[:space:]' < .saboteur/whole-suite-map-v2)
# the final triple must still be exactly the validated one (pointer swap or rewrite after the stop signal fails closed)
[ "$KEY" = "$(jq -r '.boundary.pointer_key' "$OUT/map-meta.json")" ] || { echo "MR_BLOCK: pointer changed after boundary validation" | tee -a "$L"; exit 1; }
for f in "coverage-$KEY.json" "inputs-$KEY.json" whole-suite-map-v2; do
  [ "$(sha256sum ".saboteur/$f" | cut -d' ' -f1)" = "$(jq -r --arg f "$f" '.boundary.sha256[$f]' "$OUT/map-meta.json")" ] || { echo "MR_BLOCK: $f differs from the validated bytes" | tee -a "$L"; exit 1; }
done
echo "BOUNDARY_TRIPLE_BYTES_MATCH_VALIDATED key=$KEY" | tee -a "$OUT/MAP-RECEIPT.txt"
{ echo "POINTER_KEY $KEY"; sha256sum ".saboteur/coverage-$KEY.json" ".saboteur/inputs-$KEY.json" .saboteur/whole-suite-map-v2
  echo "MAP_TEST_COUNT $(jq '.tests | length' ".saboteur/coverage-$KEY.json" 2>/dev/null || echo unreadable)"; } | tee -a "$OUT/MAP-RECEIPT.txt" | tee -a "$L"
# --- REPLAY ---
measured "$OUT/db-reset-replay-meta.json" 600 bundle exec rails db:drop db:create db:schema:load >> "$L" 2>&1 || { echo "MR_BLOCK: db reset before replay failed" | tee -a "$L"; exit 1; }
sha256sum .saboteur/whole-suite-map-v2 ".saboteur/coverage-$KEY.json" ".saboteur/inputs-$KEY.json" > "$OUT/pointer-before-replay.txt"
# Exact established replay protocol: 10 minute cap, never shrunk to fit. Not enough time = stop before starting it.
MAXM=10
[ "$(left_s)" -ge $(( MAXM * 60 + 1500 )) ] || { echo "MR_BLOCK: job time left ($(left_s)s) cannot cover the exact 10m replay plus margin; not shrinking the cap" | tee -a "$L"; exit 1; }
stamp "REPLAY_START since=$BASE baseline_passes=1 max_duration=10m" | tee -a "$L"
rc=0
measured "$OUT/replay-meta.json" $(( MAXM * 60 + 900 )) bundle exec saboteur run --since "$BASE" --baseline-passes 1 --max-duration 10m --jobs 1 --verbose --seed "$SEED" --json "$OUT/report.json" --html "$OUT/report.html" > "$OUT/replay.log" 2>&1 || rc=$?
stamp "REPLAY_END exit=$rc" | tee -a "$L"
sha256sum .saboteur/whole-suite-map-v2 ".saboteur/coverage-$KEY.json" ".saboteur/inputs-$KEY.json" > "$OUT/pointer-after-replay.txt"
mkdir -p "$OUT/replay-saboteur-dir"; cp -r .saboteur/. "$OUT/replay-saboteur-dir/" 2>/dev/null || true
exit "$rc"
