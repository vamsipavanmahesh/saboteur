#!/usr/bin/env bash
# tree_setup.sh <tree_dir> <sha> - worktree + saboteur integration + bundle + DB prepare. Logs everything.
set -uo pipefail
TREE="$1"; SHA="$2"; LOGD="$3"
export PATH=/home/sandbox/ruby343/bin:$PATH PG_HOST=/tmp/pgsock PG_USERNAME=postgres RAILS_ENV=test
export BUNDLE_PATH=/home/sandbox/bundle BUNDLE_JOBS=1 MAKEFLAGS=-j1
cd /home/sandbox/human-essentials
git worktree add --detach "$TREE" "$SHA" > "$LOGD/worktree-add.log" 2>&1 || exit 11
cd "$TREE"
git rev-parse HEAD > "$LOGD/tree-sha.txt"
mkdir -p vendor/cache && cp /home/sandbox/saboteur-src/saboteur-0.12.3.gem /home/sandbox/saboteur-src/vendor/cache/prism-*.gem vendor/cache/ || { echo "VENDOR-COPY-FAIL $TREE"; exit 17; }
# identical Gemfile addition in every tree: plain version pin; source = vendor/cache built artifact (registry not used)
printf '\n# saboteur field-run integration (built artifact from pinned source, not registry)\ngem "saboteur", "0.12.3", group: :test\n' >> Gemfile
cat > config/saboteur.rb <<'CFG'
# saboteur field-run config: human-essentials lane. CLI flags override.
Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"] # user scope: app/ or lib/ Ruby
  c.require = ["./config/environment"]
  c.rails = true
  c.jobs = 1 # serial box rule
end
CFG
timeout --signal=INT --kill-after=30 1800 bundle install --local > "$LOGD/bundle-install.log" 2>&1 || { echo "BUNDLE-FAIL $TREE (single bounded attempt, no retry)"; exit 12; }
# pin integrity: bundle payload must equal the pinned-source build (registry gem is a violation)
diff -rq /tmp/pin-verify/data/lib "$BUNDLE_PATH/ruby/3.4.0/gems/saboteur-0.12.3/lib" > "$LOGD/pin-payload-diff.txt" 2>&1 && echo "PIN-OK" || { echo "PIN-VIOLATION $TREE"; exit 18; }
git diff --stat -- Gemfile Gemfile.lock > "$LOGD/gemfile-diff.txt"
bundle exec rails db:prepare > "$LOGD/db-prepare.log" 2>&1 || { echo "DB-FAIL $TREE"; exit 13; }
echo "SETUP-OK $TREE $SHA"
