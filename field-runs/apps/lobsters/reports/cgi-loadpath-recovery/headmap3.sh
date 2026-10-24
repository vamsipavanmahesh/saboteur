#!/bin/bash
# headmap3.sh <tree-name> <attempt-id> - whole-suite map, PGID-owned, attempt-tagged logs.
# v3: fail-closed provenance preamble (lock sha, bundle list digest, saboteur version) into the map log.
set -u
T=$1; AID=$2
source ~/field-runs/env400.sh
cd ~/field-runs/pr-trees/$T || exit 64
A=~/field-runs/saboteur-field-runs/apps/lobsters
LOG=$A/logs/${T}-map-${AID}.log
{
  echo "RUNNER headmap3.sh sha256=$(sha256sum ~/field-runs/headmap3.sh | cut -d' ' -f1) attempt=$AID tree=$T head=$(git rev-parse HEAD) started=$(date -Iseconds)"
  echo "PGID=$$"; echo "SEED=${SEED:-1}"
  echo "T0=$(date +%s)"
  echo "LOCK sha256=$(sha256sum Gemfile.lock | cut -d' ' -f1)"
  echo "BUNDLE_LIST sha256=$(bundle list 2>/dev/null | sha256sum | cut -d' ' -f1)"
  echo "SABOTEUR_BIN $(bundle exec saboteur version 2>/dev/null || echo VERSION_QUERY_FAILED)"
} >> "$LOG"
export RAILS_ENV=test SABOTEUR_VERSION=0.12.3 SABOTEUR_SHA=6f87ccc98377bf0c23f3cf409006f0464c2aa67c
mkdir -p $A/reports/$T-map-$AID
python3 ~/field-runs/runmeasured.py $A/reports/$T-map-$AID map -- bundle exec saboteur run --all --verbose --jobs 1 --no-cache --seed ${SEED:-1} >> "$LOG" 2>&1
echo "HEADMAP_${T}_${AID}_EXIT=$? ended=$(date -Iseconds)" >> "$LOG"
