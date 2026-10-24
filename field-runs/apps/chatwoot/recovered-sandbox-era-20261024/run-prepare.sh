#!/bin/bash
# run-prepare.sh — HEAD-era tree prepare, original recipe order.
# RECOVERED 2026-10-24 11:40 IST from the worker's own transcript after sandbox reset #2.
# This is the reviewed v2 content (pipefail, full per-stage raw logs, real exit codes,
# --jobs 1 per D29). It carries its own new hash; the lost original's hash was
# 9d8bea7c0801f37acfe5b952328a596ac914a296cdd86733113f6d2336304ce3.
set -u
set -o pipefail
source $HOME/fieldruns/env.sh
export MAKEFLAGS=-j1
EV=$HOME/fieldruns/evidence/apps/chatwoot
mkdir -p $EV/logs $EV/reports/baseline $EV/reports/baseline-extra
log=$EV/logs/prepare.log
exec >> $log 2>&1
echo "=== PREPARE v2 $(date -Is) ==="
ruby -v; ruby -ropenssl -e 'puts "openssl: #{OpenSSL::OPENSSL_VERSION}"' || { echo "PREPARE_DONE ec=toolchain_fail"; exit 1; }
ruby -rfiddle -e 'puts "fiddle ok"'; ruby -rpsych -e 'puts "psych ok"'
psql --version; redis-cli -p 6379 ping || { echo "PREPARE_DONE ec=services_down"; exit 1; }
node -v; pnpm -v
cd $HOME/fieldruns/chatwoot-git || exit 1
echo "TREE_CHECK sha=$(git rev-parse HEAD) (expect 98a9ed710ad7334b07e96ca6c1da0b7e8ebc686a)"
if [ ! -f .env ]; then
  sed -e "s|<generate: openssl rand -hex 64>|$(openssl rand -hex 64)|" \
      $HOME/fieldruns/chatwoot.env.template > .env.gen
  awk -v a="$(openssl rand -hex 32)" -v b="$(openssl rand -hex 32)" -v c="$(openssl rand -hex 32)" '
    /^ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=/{print "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" a; next}
    /^ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=/{print "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=" b; next}
    /^ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=/{print "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=" c; next}
    {print}' .env.gen > .env && rm .env.gen
  echo "ENV_WRITTEN $(date -Is)"
fi
gem install bundler -v 2.5.16 --no-document > $EV/logs/prepare-bundler-install.log 2>&1
ec=$?; tail -1 $EV/logs/prepare-bundler-install.log; [ $ec -eq 0 ] || { echo "PREPARE_DONE ec=bundler_gem_fail"; exit 1; }
bundle config set --local path vendor/bundle && bundle config set --local without 'development'
echo "BUNDLE_INSTALL_START $(date -Is)"
bundle install --jobs 1 > $EV/logs/prepare-bundle-install.log 2>&1
ec=$?; tail -6 $EV/logs/prepare-bundle-install.log
[ $ec -eq 0 ] || { echo "PREPARE_DONE ec=bundle_fail_single_attempt real_ec=$ec (full log prepare-bundle-install.log)"; exit 1; }
echo "BUNDLE_OK $(date -Is)"
pnpm i > $EV/logs/prepare-pnpm.log 2>&1
ec=$?; tail -2 $EV/logs/prepare-pnpm.log
[ $ec -eq 0 ] || { echo "PREPARE_DONE ec=pnpm_fail real_ec=$ec (full log prepare-pnpm.log)"; exit 1; }
echo "CE_STRIP $(date -Is) mirroring run_foss_spec.yml@era (rm -rf enterprise spec/enterprise; D6 2026-10-23 21:44)"
rm -rf enterprise spec/enterprise
echo "CE_STRIP_DONE enterprise/=$([ -d enterprise ] && echo PRESENT || echo ABSENT) spec/enterprise=$([ -d spec/enterprise ] && echo PRESENT || echo ABSENT)"
echo "DB_SETUP_START $(date -Is)"
bundle exec rake db:create db:schema:load > $EV/logs/prepare-db.log 2>&1
ec=$?; tail -3 $EV/logs/prepare-db.log
[ $ec -eq 0 ] || { echo "PREPARE_DONE ec=db_fail real_ec=$ec (full log prepare-db.log)"; exit 1; }
echo "SMOKE_START $(date -Is)"
bundle exec rspec spec/models/account_spec.rb --format progress > $EV/logs/prepare-smoke.log 2>&1
smoke_ec=$?
tail -3 $EV/logs/prepare-smoke.log
echo "PREPARE_DONE ec=$smoke_ec stage=smoke $(date -Is) (full log prepare-smoke.log)"
exit $smoke_ec
