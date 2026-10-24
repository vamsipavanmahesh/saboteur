#!/bin/bash
# Scoped per-PR-tree green checks: for each selected PR, on base and head trees,
# run only the replay-scope spec files that EXIST in that tree.
source ~/field/env.sh
REPO=~/field/solidus/repo
OUT=~/field/runs/apps/solidus
SCOPE="spec/models/spree/stock spec/models/spree/order_cancellations_spec.rb spec/models/spree/unit_cancel_spec.rb spec/models/spree/payment_method/bogus_credit_card_spec.rb spec/helpers/base_helper_spec.rb"
while IFS=, read -r pr base head src spec tot url; do
  case "$pr" in \#*|pr) continue;; esac
  for side in base head; do
    sha=$([ $side = base ] && echo $base || echo $head)
    dir=~/field/solidus/trees/pr${pr}-${side}
    [ -d "$dir" ] || git -C $REPO worktree add --detach "$dir" "$sha" >/dev/null 2>&1
    cd "$dir/core" || exit 1
    existing=""
    for f in $SCOPE; do [ -e "$f" ] && existing="$existing $f"; done
    scen=pr${pr}-${side}-scope
    echo "=== $scen $(date -u +%FT%TZ) sha=$sha specs:${existing} ==="
    bundle install --quiet 2>&1 | tail -2; test ${PIPESTATUS[0]} -eq 0 || { echo "BUNDLE_INSTALL_FAILED $scen"; exit 1; }
    ~/field/measure.sh baseline "$OUT/reports/$scen" base_sha=$sha head_sha=$sha pr_url=$url saboteur_version=null saboteur_sha=null -- \
      bundle exec rspec $existing --format progress --format json --out "$OUT/logs/${scen}-rspec.json"
    grep -h . "$OUT/reports/$scen/measurement.json" | head -0
  done
done < $OUT/selection.csv
echo "ALL_TREE_CHECKS_DONE $(date -u +%FT%TZ)"
