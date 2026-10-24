#!/bin/bash
# run-map3.sh — HEAD-era whole-suite map, post-rebuild. chatwoot-git tree, vendor/bundle
# (original recipe route). watch4 armed; attempt_start_epoch captured BEFORE saboteur launch.
set -u
set -o pipefail
source $HOME/fieldruns/env.sh
export MAKEFLAGS=-j1
EV=$HOME/fieldruns/evidence/apps/chatwoot
HEAD_ERA=98a9ed710ad7334b07e96ca6c1da0b7e8ebc686a
WT=$HOME/fieldruns/chatwoot-git
mkdir -p $EV/maps/head-era $EV/reports/map-head-era
log=$EV/logs/map-head-era.log
exec >> $log 2>&1
echo "=== MAP3 head-era attempt $(date -Is) ==="
echo "SCRIPT_SHA256 $(sha256sum $HOME/fieldruns/run-map3.sh | cut -d' ' -f1)"
echo "WATCH4_SHA256 $(sha256sum $HOME/fieldruns/map-boundary-watch4.sh | cut -d' ' -f1)"
gem generate_index --directory $HOME/fieldruns/local-gems > $EV/logs/map-gem-index.log 2>&1
tail -1 $EV/logs/map-gem-index.log
cd $WT || exit 1
echo "TREE_CHECK sha=$(git rev-parse HEAD) (expect $HEAD_ERA)"
python3 - <<'PYEOF'
t=open('Gemfile').read()
anchor="group :test do"
add="\n  # FIELD RUN: saboteur 0.12.3 BUILT ARTIFACT from fixed source 6f87ccc98377bf0c23f3cf409006f0464c2aa67c via LOCAL FILE SOURCE (registry 0.12.3 differs in 18 lib files - not the pinned source; artifact sha256 57ac8099a6f78ff713d6f361ef7e14632ca1676acdec02d15adcab46f0ca0dd4)\n  gem 'saboteur', '= 0.12.3', source: 'file:///home/sandbox/fieldruns/local-gems'\n  # FIELD RUN: fiddle gem added (source-built ruby skipped the default fiddle ext)\n  gem 'fiddle'\n"
if "saboteur" not in t:
    t=t.replace(anchor, anchor+add,1)
elif "fiddle" not in t:
    t=t.replace(anchor, anchor+"\n  # FIELD RUN: fiddle gem added (source-built ruby skipped the default fiddle ext)\n  gem 'fiddle'\n",1)
open('Gemfile','w').write(t)
PYEOF
grep -n "saboteur\|fiddle" Gemfile | grep -v "^.*#" | head -3
bundle install > $EV/logs/map-bundle-install.log 2>&1
ec=$?; tail -4 $EV/logs/map-bundle-install.log
[ $ec -eq 0 ] || { echo "MAP_DONE ec=bundle_fail_single_attempt real_ec=$ec (full log map-bundle-install.log)"; exit 1; }
echo "BUNDLE_OK $(date -Is)"
grep -B1 -A2 "saboteur (0.12.3)" Gemfile.lock | head -6
echo "GENERATOR_START $(date -Is)"
bundle exec rails generate saboteur:install 2>&1 | tail -3
echo "GENERATOR_END $(date -Is)"
proof=$(bundle exec ruby -e 'require "saboteur"; s=Gem.loaded_specs["saboteur"]; print "#{s.version} #{s.full_gem_path}"' 2>&1) \
  && echo "ARTIFACT_PROOF $proof" || { echo "ARTIFACT_PROOF_FAILED $proof"; echo "MAP_DONE ec=artifact_fail"; exit 1; }
rm -rf /tmp/ours && mkdir -p /tmp/ours && gem unpack $HOME/fieldruns/local-gems/gems/saboteur-0.12.3.gem --target /tmp/ours >/dev/null 2>&1
(cd /tmp/ours/saboteur-0.12.3 && find lib -type f | sort | xargs sha256sum 2>/dev/null) > /tmp/artifact-lib.sha256
inst=$(bundle exec ruby -e 'print Gem.loaded_specs["saboteur"].full_gem_path' 2>/dev/null)
(cd $inst && find lib -type f | sort | xargs sha256sum 2>/dev/null) > /tmp/installed-lib.sha256
if diff -q /tmp/artifact-lib.sha256 /tmp/installed-lib.sha256 >/dev/null; then
  echo "INSTALLED_LIB_DIGEST MATCH built-artifact-lib ($(wc -l < /tmp/artifact-lib.sha256) files)"
else
  echo "INSTALLED_LIB_DIGEST MISMATCH:"; diff /tmp/artifact-lib.sha256 /tmp/installed-lib.sha256 | head -6
  echo "MAP_DONE ec=artifact_mismatch"; exit 1
fi
echo "SCHEMA_LOAD_START $(date -Is)"
RAILS_ENV=test bundle exec rails db:schema:load > $EV/logs/map-schema-load.log 2>&1
ec=$?; tail -2 $EV/logs/map-schema-load.log
[ $ec -eq 0 ] || { echo "MAP_DONE ec=schema_fail real_ec=$ec (full log map-schema-load.log)"; exit 1; }
echo "SCHEMA_LOAD_END $(date -Is)"
for f in Gemfile.lock config/saboteur.rb config/saboteur_custom_map.rb config/saboteur_ignore.rb; do
  h=$(sha256sum $f 2>/dev/null | cut -c1-16); echo "PFX $f ${h:-ABSENT}"
done > $EV/maps/head-era/prefix-map-era.txt
echo "PRE_RUN_SABOTEUR_DIR: $(ls -A .saboteur 2>/dev/null | tr '\n' ' ' || echo ABSENT)"
ASTART=$(date +%s)
timeout --signal=INT --kill-after=30 2700 bundle exec saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose --json $EV/reports/map-head-era/map-report.json &
SABPID=$!
tstart=$(awk '{print $22}' /proc/$SABPID/stat)
cp $HOME/fieldruns/map-boundary-watch4.sh /tmp/watch4-head-era-$SABPID.sh && chmod +x /tmp/watch4-head-era-$SABPID.sh
echo "WATCHER_COPY_SHA256 $(sha256sum /tmp/watch4-head-era-$SABPID.sh | cut -d' ' -f1) path=/tmp/watch4-head-era-$SABPID.sh"
nohup /tmp/watch4-head-era-$SABPID.sh $WT $SABPID $tstart $ASTART >> $log 2>&1 &
WATCHER=$!
echo "MAP_START $(date -Is) sabpid=$SABPID sabstart=$tstart watcher=$WATCHER attempt_start_epoch=$ASTART (watch4: owned identity + freshness gate + inputs-key binding)"
wait $SABPID; status=$?
echo "MAP_EXIT=$status $(date -Is) (130 with MAP_BOUNDARY_SIGINT_SENT verified_pid=$SABPID = deliberate MAP_BOUNDARY_STOP, not PASS)"
kill $WATCHER 2>/dev/null
echo "ARTIFACT_MTIMES:"; stat -c '%n %y' .saboteur/coverage-*.json .saboteur/inputs-*.json .saboteur/whole-suite-map-v2 2>/dev/null
cov=$(ls .saboteur/coverage-*.json 2>/dev/null | head -1)
if [ -n "$cov" ]; then
  echo "MAP_DIGEST $(sha256sum $cov | cut -d' ' -f1) file=$(basename $cov)"
  echo "MAP_TEST_COUNT $(python3 -c "import json;m=json.load(open('$cov'));print(len(m.get('tests',[])))" 2>&1)"
  echo "MAP_POINTER_KEY $(cat .saboteur/whole-suite-map-v2)"
  cp .saboteur/coverage-*.json .saboteur/inputs-*.json .saboteur/whole-suite-map-v2 $EV/maps/head-era/ && echo "MAP_CACHE_SAVED $(ls $EV/maps/head-era/ | tr '\n' ' ')"
  ckey=$(cat .saboteur/whole-suite-map-v2 | tr -d '[:space:]')
  mcount=$(python3 -c "import json;print(len(json.load(open('.saboteur/coverage-$ckey.json')).get('tests',[])))" 2>/dev/null)
  if [ -z "$mcount" ] || [ "$mcount" = "0" ]; then
    echo "MAP_RECEIPTS_INVALID coverage JSON unparseable or test count empty/0 (ckey=$ckey) - map receipt NOT written, row not consumable"
    echo "MAP_DONE ec=$status result=map_receipt_invalid"
    exit 1
  fi
  {
    echo "map_attempt_start_epoch=$ASTART"
    echo "pointer_key=$ckey"
    echo "coverage_digest=$(sha256sum .saboteur/coverage-$ckey.json | cut -d' ' -f1)"
    echo "map_test_count=$mcount"
    echo "map_exit=$status"
    echo "saved_at=$(date -Is)"
  } > $EV/maps/head-era/map-receipts.env
  echo "MAP_RECEIPTS_WRITTEN maps/head-era/map-receipts.env tests=$mcount"
  echo "MAP_DONE ec=$status result=map_built"
else
  echo "MAP_CACHE_INCOMPLETE (baseline red or build failed; see log)"
  echo "MAP_DONE ec=$status result=map_failed"
fi
