#!/bin/bash
# usage: measure.sh <kind> <outdir> <extra-json-kv...> -- <command...>
# writes <outdir>/measurement.json and <outdir>/stdout+stderr.log
KIND=$1; OUT=$2; shift 2
EXTRA=""
while [ "$1" != "--" ]; do EXTRA="$EXTRA$1 "; shift; done
shift
mkdir -p "$OUT"
START=$(date -u +%FT%TZ); SE=$(date +%s)
"$@" > "$OUT/stdout+stderr.log" 2>&1 &
PID=$!
PEAK=0
while kill -0 $PID 2>/dev/null; do
  RSS=$(ps -o rss= --ppid $PID -p $PID 2>/dev/null | awk '{s+=$1} END {print s+0}')
  [ "$RSS" -gt "$PEAK" ] && PEAK=$RSS
  sleep 1
done
wait $PID; RC=$?
END=$(date -u +%FT%TZ); WALL=$(( $(date +%s) - SE ))
python3 - "$OUT/measurement.json" <<PYEOF
import json,sys
m={"kind":"$KIND","status":"done","command":$(python3 -c "import json,sys;print(json.dumps(' '.join(sys.argv[1:])))" "$@"),
   "started_at":"$START","ended_at":"$END","wall_seconds":$WALL,"exit_code":$RC,
   "peak_rss_kb":$PEAK}
for kv in """$EXTRA""".split():
    k,v=kv.split("=",1); m[k]=None if v=="null" else v
json.dump(m,open(sys.argv[1],"w"),indent=2)
print(open(sys.argv[1]).read())
PYEOF
