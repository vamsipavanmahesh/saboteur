#!/bin/bash
# map-boundary-watch4.sh <tree_dir> <target_pid> <target_starttime_ticks> <attempt_start_epoch>
# watch3 + audit adds: inputs file must be inputs-<ckey>.json bound to the SELECTED
# coverage key (not the newest inputs-*); failed kill is logged. Call site must capture
# attempt_start_epoch BEFORE launching the saboteur process.
wt=$1; dir=$1/.saboteur; tpid=$2; tstart=$3; astart=$4
deadline=$(( $(date +%s) + 3300 ))
verify() {
  [ -d /proc/$tpid ] || return 1
  local st; st=$(awk '{print $22}' /proc/$tpid/stat 2>/dev/null)
  [ "$st" = "$tstart" ] || return 1
  tr '\0' ' ' < /proc/$tpid/cmdline 2>/dev/null | grep -q "saboteur run" || return 1
  return 0
}
while [ $(date +%s) -lt $deadline ]; do
  sleep 20
  verify || { echo "WATCH4_EXIT target gone or identity changed $(date -Is)"; exit 0; }
  cov=$(ls -t $dir/coverage-*.json 2>/dev/null | head -1)
  ptr=$dir/whole-suite-map-v2
  { [ -n "$cov" ] && [ -f "$ptr" ]; } || continue
  ckey=$(basename "$cov" .json); ckey=${ckey#coverage-}
  inp=$dir/inputs-$ckey.json
  [ -f "$inp" ] || { echo "WATCH4_INPUTS_MISSING expected=inputs-$ckey.json $(date -Is)"; continue; }
  fresh=1
  for f in "$cov" "$inp" "$ptr"; do
    mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$mt" -ge "$astart" ] || { fresh=0; echo "WATCH4_STALE_IGNORED file=$f mtime=$mt < attempt_start=$astart $(date -Is)"; break; }
  done
  [ $fresh -eq 1 ] || continue
  s1=$(stat -c%s "$cov" "$inp" "$ptr" 2>/dev/null | tr '\n' ',')
  sleep 12
  verify || { echo "WATCH4_EXIT target changed mid-check $(date -Is)"; exit 0; }
  s2=$(stat -c%s "$cov" "$inp" "$ptr" 2>/dev/null | tr '\n' ',')
  [ "$s1" = "$s2" ] || continue
  python3 -c "import json;json.load(open('$cov'))" 2>/dev/null || continue
  key=$(tr -d '[:space:]' < "$ptr")
  [ "$key" = "$ckey" ] || { echo "WATCH4_KEY_MISMATCH pointer=$key cov=$ckey $(date -Is)"; continue; }
  verify || { echo "WATCH4_EXIT target changed before signal $(date -Is)"; exit 0; }
  echo "MAP_BOUNDARY_STABLE cov=$(basename $cov) inputs=$(basename $inp) pointer_key=$key target_pid=$tpid starttime=$tstart attempt_start=$astart $(date -Is)"
  if kill -INT $tpid; then
    echo "MAP_BOUNDARY_SIGINT_SENT verified_pid=$tpid verified_starttime=$tstart $(date -Is)"
  else
    echo "MAP_BOUNDARY_KILL_FAILED pid=$tpid starttime=$tstart errno=$? $(date -Is)"
  fi
  exit 0
done
echo "WATCH4_EXIT deadline reached without boundary $(date -Is)"
