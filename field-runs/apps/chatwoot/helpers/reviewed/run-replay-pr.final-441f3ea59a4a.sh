#!/bin/bash
# run-replay-pr.sh <pr_number> <base_sha> <head_sha> <era_label> — scoped same-era replay, cache ON.
# Preconditions: this era's whole-suite map exists in this tree's .saboteur (pointer +
# coverage + inputs, mtime >= that map's attempt_start). A replay NEVER refreshes the pointer.
set -u
set -o pipefail
source $HOME/fieldruns/env.sh
export MAKEFLAGS=-j1
PR=$1; BASE=$2; HEAD=$3; ERA=$4
EV=$HOME/fieldruns/evidence/apps/chatwoot
WT=$HOME/fieldruns/chatwoot-git
OUT=$EV/reports/pr-$PR
mkdir -p $OUT
log=$EV/logs/pr-$PR.log
exec >> $log 2>&1
echo "=== REPLAY pr-$PR $(date -Is) base=$BASE head=$HEAD ==="
echo "SCRIPT_SHA256 $(sha256sum $HOME/fieldruns/run-replay-pr.sh | cut -d' ' -f1)"
cd $WT || exit 1
# --- map-consumption pre-receipts (whole pointer, not selection cache) ---
MR=$EV/maps/$ERA/map-receipts.env
[ -f "$MR" ] || { echo "REPLAY_DONE pr=$PR ec=no_map_receipts era=$ERA"; exit 1; }
source $MR
ptr=$WT/.saboteur/whole-suite-map-v2
[ -f "$ptr" ] || { echo "REPLAY_DONE pr=$PR ec=no_whole_map_pointer"; exit 1; }
key=$(tr -d '[:space:]' < $ptr)
if [ "$key" != "$pointer_key" ]; then
  echo "POINTER_KEY != map-receipts recorded key ($key != $pointer_key) - wrong era map in tree; row INVALID"
  echo "REPLAY_DONE pr=$PR ec=era_pointer_mismatch result=invalid_row"
  exit 1
fi
echo "MAP_RECEIPTS_BOUND era=$ERA map_attempt_start_epoch=$map_attempt_start_epoch map_test_count=$map_test_count"
cov=$WT/.saboteur/coverage-$key.json
inp=$WT/.saboteur/inputs-$key.json
[ -f "$cov" ] && [ -f "$inp" ] || { echo "REPLAY_DONE pr=$PR ec=pointer_target_missing key=$key"; exit 1; }
echo "PRE_POINTER_KEY $key"
echo "PRE_COVERAGE_DIGEST $(sha256sum $cov | cut -d' ' -f1) file=coverage-$key.json"
echo "PRE_MAP_TEST_COUNT $(python3 -c "import json;print(len(json.load(open('$cov')).get('tests',[])))")"
echo "PRE_INPUTS_PRESENT inputs-$key.json $(sha256sum $inp | cut -c1-16)"
echo "PRE_ARTIFACT_MTIMES:"; stat -c '%n %y' "$cov" "$inp" "$ptr"
# --- tree setup for this era ---
git checkout --force $HEAD || { echo "REPLAY_DONE pr=$PR ec=checkout_fail"; exit 1; }
echo "TREE_CHECK sha=$(git rev-parse HEAD) (expect $HEAD)"
if [ -d enterprise ]; then echo "EE_DIR_PRESENT enterprise/ ($(find enterprise -name '*_spec.rb' 2>/dev/null | wc -l) spec files) - exclusion per era logged"; fi
python3 - <<'PYEOF'
t=open('Gemfile').read()
anchor="group :test do"
add="\n  # FIELD RUN: saboteur 0.12.3 BUILT ARTIFACT from fixed source 6f87ccc98377bf0c23f3cf409006f0464c2aa67c via LOCAL FILE SOURCE (artifact sha256 57ac8099a6f78ff713d6f361ef7e14632ca1676acdec02d15adcab46f0ca0dd4)\n  gem 'saboteur', '= 0.12.3', source: 'file:///home/sandbox/fieldruns/local-gems'\n  # FIELD RUN: fiddle gem added (source-built ruby skipped the default fiddle ext)\n  gem 'fiddle'\n"
if "saboteur" not in t:
    t=t.replace(anchor, anchor+add,1)
open('Gemfile','w').write(t)
PYEOF
bundle install --jobs 1 > $OUT/bundle-install.log 2>&1
ec=$?; tail -4 $OUT/bundle-install.log
[ $ec -eq 0 ] || { echo "REPLAY_DONE pr=$PR ec=bundle_fail real_ec=$ec"; exit 1; }
echo "BUNDLE_OK $(date -Is)"
bundle exec rails generate saboteur:install > $OUT/generator.log 2>&1 || true
tail -2 $OUT/generator.log
for f in Gemfile.lock config/saboteur.rb config/saboteur_custom_map.rb config/saboteur_ignore.rb; do
  h=$(sha256sum $f 2>/dev/null | cut -c1-16); echo "PFX $f ${h:-ABSENT}"
done > $OUT/prefix-replay.txt
if diff $EV/maps/$ERA/prefix-map-era.txt $OUT/prefix-replay.txt > $OUT/prefix-diff.txt 2>&1; then
  echo "PREFIX MATCH (vs maps/$ERA/prefix-map-era.txt)"
else
  echo "PREFIX MISMATCH vs map-era dump:"; cat $OUT/prefix-diff.txt
  echo "REPLAY_DONE pr=$PR ec=prefix_mismatch result=invalid_row (map/root/runtime/config/lock mismatch - no qualified whole confirmation)"
  exit 1
fi
echo "SCHEMA_LOAD_START $(date -Is)"
RAILS_ENV=test bundle exec rails db:schema:load > $OUT/schema-load.log 2>&1
ec=$?; tail -2 $OUT/schema-load.log
[ $ec -eq 0 ] || { echo "REPLAY_DONE pr=$PR ec=schema_fail real_ec=$ec"; exit 1; }
# --- scoped replay, whole-map cache ON ---
ASTART=$(date +%s)
echo "REPLAY_START $(date -Is) attempt_start_epoch=$ASTART"
timeout --signal=INT --kill-after=30 2700 bundle exec saboteur run --since $BASE --baseline-passes 1 --max-duration 35m --jobs 1 --verbose --json $OUT/report.json > $OUT/saboteur-stdout.log 2>&1
status=$?
echo "REPLAY_EXIT=$status $(date -Is)"
# --- post receipts: pointer must be UNCHANGED ---
key2=$(tr -d '[:space:]' < $ptr 2>/dev/null)
echo "POST_POINTER_KEY $key2 (pre=$key)"
echo "POST_COVERAGE_DIGEST $(sha256sum $cov 2>/dev/null | cut -d' ' -f1)"
if [ "$key2" != "$key" ]; then
  echo "POINTER_CHANGED_DURING_REPLAY - a scoped replay must never rewrite the whole pointer; row INVALID"
  echo "REPLAY_DONE pr=$PR ec=pointer_changed result=invalid_row"
  exit 1
fi
if [ ! -f $OUT/report.json ]; then
  echo "REPLAY_DONE pr=$PR ec=no_report result=invalid_row (saboteur exit $status, no report written)"
  exit 1
fi
python3 - <<PYEOF > $OUT/receipts.env 2>$OUT/receipts-extract.err
import json, sys
r=json.load(open('$OUT/report.json'))
sab=r['saboteur']                      # hard fail if schema absent
f=sab['findings']
scores=sab['scores']['all']            # totals live here, NOT in a summary key
surv=f['survivors']                    # live unignored survivor OBJECTS
order=f['order']                       # digest STRINGS, terminal order
assert isinstance(order, list) and all(isinstance(d,str) for d in order), "findings.order must be digest strings"
accepted=f.get('accepted',[])
print("REPORT_SURVIVORS", len(surv))
print("REPORT_ACCEPTED", len(accepted))
print("REPORT_SURVIVORS_TRUNCATED", f.get('survivorsTruncated',0))
print("REPORT_SCORES_ALL", json.dumps(scores, sort_keys=True))
print("REPORT_COMPLETE", sab.get('complete'))
print("REPORT_EXIT_CAUSE", sab.get('exitCause',''))
survd={x['digest'] for x in surv}
top=next((d for d in order if d in survd), None)
print("TOP_FINDING_DIGEST", top if top else "NONE")
for x in surv:
    # verbatim survivor object: confirmation/pin fields are taken as-is if the
    # report carries them; nothing is invented or relabelled here.
    print("SURVIVOR_OBJECT", json.dumps(x, sort_keys=True))
PYEOF
ec=$?
if [ $ec -ne 0 ]; then
  echo "RECEIPT_EXTRACTION_FAILED (see receipts-extract.err) - derived receipt INVALID, raw report preserved at $OUT/report.json"
  echo "REPLAY_DONE pr=$PR ec=receipt_extract_fail result=invalid_row"
  exit 1
fi
cat $OUT/receipts.env
# verbatim stdout lines for survivor digests (confirmation evidence outside the JSON)
grep -F -f <(grep '^SURVIVOR_OBJECT' $OUT/receipts.env | python3 -c "import sys,json;[print(json.loads(l.split(' ',1)[1])['digest']) for l in sys.stdin]") $OUT/saboteur-stdout.log > $OUT/survivor-stdout-verbatim.txt 2>/dev/null || true
echo "STDOUT_VERBATIM_LINES $(wc -l < $OUT/survivor-stdout-verbatim.txt) -> survivor-stdout-verbatim.txt"
echo "REPLAY_DONE pr=$PR ec=$status result=report_written"
exit 0
