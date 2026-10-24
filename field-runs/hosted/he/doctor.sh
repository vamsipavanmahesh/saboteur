#!/usr/bin/env bash
# doctor.sh: ONE native `saboteur doctor --suite` at the doctor tree (PR 5723 head). At the pin this runs the unchanged suite twice
# (doctor_command.rb:14, baseline_health.rb check_run(1) and check_run(2)); no second invocation is made.
source "$(dirname "$0")/lib.sh"
SHA=$(row 5723 | awk '{print $2}'); L="$OUT/doctor.log"
bash "$RECIPE_DIR/prep.sh" "$SHA" || { echo "DOCTOR_VERDICT=BLOCKED prep failed" | tee -a "$L"; exit 1; }
bash "$RECIPE_DIR/dbassets.sh" || { echo "DOCTOR_VERDICT=BLOCKED db/assets failed" | tee -a "$L"; exit 1; }
cd "$APP_ROOT"
NEED=$(( 2 * 3600 + 2400 ))
[ "$(left_s)" -ge $(( NEED + 900 )) ] || { echo "DOCTOR_VERDICT=BLOCKED job time left ($(left_s)s) cannot cover two 3600s passes plus margin; cap not shrunk" | tee -a "$L"; exit 1; }
stamp "DOCTOR_START cmd='bundle exec saboteur doctor --suite' cap=${NEED}s" | tee -a "$L"
rc=0; measured "$OUT/doctor-meta.json" "$NEED" bash -c 'bundle exec saboteur doctor --suite > "$0" 2>&1' "$OUT/doctor-raw.log" || rc=$?
stamp "DOCTOR_END exit=$rc" | tee -a "$L"
ok=$(grep -c -E '^Baseline: [0-9]+ tests passed twice in the same order with seed' "$OUT/doctor-raw.log" || true)
if [ "$rc" = 0 ] && [ "$ok" = 1 ] && [ "$(jq -r '.stopped_by // empty' "$OUT/doctor-meta.json")" = "" ]; then
  grep -E '^Baseline:' "$OUT/doctor-raw.log" | tee -a "$L"
  echo "DOCTOR_VERDICT=PASS (one invocation, two internal passes, tree $SHA)" | tee "$OUT/DOCTOR-VERDICT.txt"
else
  echo "DOCTOR_VERDICT=RED_OR_INCOMPLETE exit=$rc success_lines=$ok stopped_by=$(jq -r '.stopped_by // "none"' "$OUT/doctor-meta.json"); raw preserved; no exclusion or replacement applies without a recorded per-tree failure and a reviewed decision" | tee "$OUT/DOCTOR-VERDICT.txt"
  exit 1
fi
