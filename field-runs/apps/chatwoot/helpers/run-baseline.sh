#!/bin/bash
source ~/fieldruns/env.sh
cd ~/fieldruns/chatwoot-git
EV=~/fieldruns/evidence/apps/chatwoot
echo "started_at=$(date -Iseconds)" > $EV/reports/baseline/meta.env
t0=$(date +%s)
# peak-RSS sampler on the rspec process group
bundle exec rspec spec/models spec/services --format progress --format json --out $EV/logs/baseline-rspec.json > $EV/logs/baseline-rspec.log 2>&1 &
RPID=$!
peak=0
while kill -0 $RPID 2>/dev/null; do
  cur=$(ps -o rss= --ppid $RPID -p $RPID 2>/dev/null | awk '{s+=$1} END {print s+0}')
  [ -n "$cur" ] && [ "$cur" -gt "$peak" ] && peak=$cur
  sleep 2
done
wait $RPID; ec=$?
t1=$(date +%s)
{
  echo "exit_code=$ec"
  echo "ended_at=$(date -Iseconds)"
  echo "wall_seconds=$((t1-t0))"
  echo "peak_rss_kb=$peak (2s sampler, sum of VmRSS over rspec process tree; method note)"
} >> $EV/reports/baseline/meta.env
echo BASELINE_DONE ec=$ec wall=$((t1-t0))s
