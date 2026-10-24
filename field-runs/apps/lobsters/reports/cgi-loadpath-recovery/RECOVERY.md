# Lobsters recovery checkpoint

Tool source: 6f87ccc98377bf0c23f3cf409006f0464c2aa67c; version 0.12.3. New archive payload verified against all pin files (238 packaged files, zero differences/extras, no missing lib/exe). New archive hash in payload-verification.json.

Rebuilt controls, not replacements for original measurement artifacts:
- 2178 HEAD c7dce360bf6173244712e6fdd72136a0e318b7c7, BASE d44b5012e74cee0b61265f48e8063255ef65592d: fresh DB, seed 3, each 842 examples / 0 failures.
- 2158 HEAD af7b9b4df3337c439e98dbfcf23f39be1b75b455, BASE 87b1befae8c51818c70aed14430bd101c7e636a6: fresh DB, seed 3, each 837 examples / 0 failures.
- Before each control: RAILS_ENV=test bundle exec rails db:drop db:create db:schema:load. Control command: RAILS_ENV=test bundle exec rspec --seed 3.
- Seed 3 is the previously selected baseline-order workaround after red probes at other seeds. Not a root-cause fix or a general stability claim. No exclusions applied.

Load-path correction: historical env.sh explicitly prepends Ruby core dirs. In reconstruction that loaded Ruby 4's cgi.rb compatibility stub instead of activated lock-pinned cgi 0.5.1. The actual gem implements CGI.parse at cgi/core.rb:396. env400.sh now prepends the same locked gem's lib dir before core dirs. No dependency version substitution or app code edit. Original failed BASE control preserved; corrected controls separately named.

Historical scope: published env.sh contains the same core-dir ordering. Earlier claim 'CGI.parse removed from cgi 0.5.1' is retracted. Earlier CGI baseline diagnosis and any proposed upstream defect claim require independent review. A scan of available published report.json mutant subject/statusReason/replacement fields and Github file paths found no CGI/Github mutant matches; this does not prove absence of all indirect effects or scan unarchived logs. Completed rows must not be invalidated by assumption. No new causal CGI conclusion is admitted by this packet.

Four lock proofs preserve every era gem/platform version; additions only fiddle 1.1.8 and saboteur 0.12.3. fiddle is explicitly pinned in the reconstructed Gemfile, so lock hashes intentionally differ from historical bounded locks. No manual lock edit, checksum bypass, or registry tool substitution.

Execution boundary: no replacement measured M/R launched. The currently exposed foreground execution timeout is 120 seconds. No supported durable arbitrary-process route has been established. Do not launch the several-minute whole-suite map as an orphaned shell child. Remaining work: supported long-lived executor, 2178 M+R and 2158 M+R at seed 3, structured fake-kill gates, fresh independent survivor qualification, portable publication.
