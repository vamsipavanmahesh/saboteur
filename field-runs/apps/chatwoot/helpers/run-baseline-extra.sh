#!/bin/bash
source ~/fieldruns/env.sh
cd ~/fieldruns/chatwoot-git
EV=~/fieldruns/evidence/apps/chatwoot
echo "started_at=$(date -Iseconds)" > $EV/reports/baseline-extra/meta.env
t0=$(date +%s)
bundle exec rspec spec/mailboxes/imap/imap_mailbox_spec.rb spec/jobs/trigger_scheduled_items_job_spec.rb --format progress --format json --out $EV/logs/baseline-extra-rspec.json > $EV/logs/baseline-extra-rspec.log 2>&1
ec=$?
t1=$(date +%s)
printf "exit_code=%s\nended_at=%s\nwall_seconds=%s\n" "$ec" "$(date -Iseconds)" "$((t1-t0))" >> $EV/reports/baseline-extra/meta.env
echo EXTRA_DONE ec=$ec
