# PR 2197 survivor triage case packet (independent field-run verification)
- PR: lobsters/lobsters #2197 "Add missing titles for some pages"; head 46fbcdf2ffaa0d066847d984c0f9975010a7c2ac; base (--since) 01a8041f9447921c86c73f83c3385966e49a2879
- Era: proofs run 2026-10-24 12:13:58-12:21:21 IST on fresh worktree tree-2197 at PR head
- Runtime: ruby 4.0.0 (2025-12-25 revision 553f1675f3) +PRISM [x86_64-linux]; saboteur path-gem 0.12.3 at pinned commit 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (bundle exec)
- Packet source: pr2197-corrective.tar-f75adf09.gz sha256 0ef6c5bb2d85927105ca165eec2444394f1ad1c4a4778d87910824dee7db9084 (FINAL corrective; supersedes pr2197-ex2 provisional 25M/11K/14S). 36 mutants, 14K (2 assertion + 12 crash), 22 survived=UNCONFIRMED, 94.71s. Packet EX2: CSS lint 14 examples omitted (head/base red) - packet's own deviation; verifier proofs do not assume it.
- Covering set (packet --test union): spec/controllers/{inbox,messages}_controller_spec.rb + spec/features/{comment,mod_domains}_spec.rb + spec/requests/{mod/reparents,mod_mails,search}_spec.rb
- Reconciliation: all 14 provisional IDs present in the final 22 with identical IDs/operators/lines (exact set match); new 8 = 6 Mod::DomainsController#edit + 2 SettingsController#index. No ID guessed or reconstructed.

## Survivors and proofs (all REAL GAP, unit level; whole-existing-suite UNCONFIRMED)
| ID (full) | Subject:line | Operator | Edit | Existing 7 files | Probe kill |
|---|---|---|---|---|---|
| 265ba36e379f861c | InboxController#all:17 | statement_removal | remove @title = "Inbox" | 39/0 | I1 |
| 8ff5c5c19270c92b | InboxController#all:17 | literal_string | "Inbox" -> "" | 39/0 | I1 |
| 45122517a7ddc0c8 | Mod::DomainsController#edit:18-19 | body_nil | both lines -> nil | 39/0 | D1 |
| 9a31f624b2f1c8d4 | Mod::DomainsController#edit:18 | statement_removal | remove @title line | 39/0 | D1 |
| a0cee31e8852087b | Mod::DomainsController#edit:19 | statement_removal | remove @title_h1 = false | 39/0 | D2 |
| f480c446a09839fa | Mod::DomainsController#edit:19 | literal_boolean | false -> true | 39/0 | D2 |
| f98739566ebb7713 | Mod::DomainsController#edit:18 | interpolation_removal | drop "Edit Domain " | 39/0 | D1 |
| d3ef739e94f76ceb | Mod::DomainsController#edit:18 | interpolation_removal | drop #{params[:id]} | 39/0 | D1 |
| ee7636cfd988297a | Mod::ReparentsController#new:6-7 | body_nil | both lines -> nil | 39/0 | R1 |
| 16ca5c211943b17d | Mod::ReparentsController#new:6 | statement_removal | remove @title line | 39/0 | R1 |
| 7628a88b22719ecf | Mod::ReparentsController#new:7 | statement_removal | remove @title_h1 = false | 39/0 | R2 |
| 6384cf5436c30d89 | Mod::ReparentsController#new:7 | literal_boolean | false -> true | 39/0 | R2 |
| 111b8e283f0397ea | Mod::ReparentsController#new:6 | interpolation_removal | drop "Reparent " | 39/0 | R1 |
| aa15cc2fbfadb177 | Mod::ReparentsController#new:6 | interpolation_removal | drop #{@reparent_user.username} | 39/0 | R1 |
| 85a0d301c72ae598 | ModMailsController#index:5 | statement_removal | remove @title = "ModMail" | 39/0 | M1 |
| cac125b5b23f254f | ModMailsController#index:5 | literal_string | "ModMail" -> "" | 39/0 | M1 |
| 82e793cd9460447c | SettingsController#index:9 | statement_removal | remove @title = "Settings" | 39/0 | SE1 |
| f55b6ebc7e08c7bf | SettingsController#index:9 | literal_string | "Settings" -> "" | 39/0 | SE1 |
| 7a2eb67c33630d46 | SearchController#index:19 | condition_true | cond -> true | 39/0 | S2 |
| 721be5b96d2f1bf9 | SearchController#index:19 | condition_false | cond -> false | 39/0 | S1 |
| b3c29e6d9b83c93b | SearchController#index:19 | negation_removal | !x.nil? -> x.nil? | 39/0 | S1+S2 |
| d1902dce1d6c0bed | SearchController#index:19 | literal_string | "Search results" -> "" | 39/0 | S1 |

Live order (packet findings.order): ee7636cfd988297a 111b8e283f0397ea 16ca5c211943b17d aa15cc2fbfadb177 721be5b96d2f1bf9 7a2eb67c33630d46 b3c29e6d9b83c93b d1902dce1d6c0bed 45122517a7ddc0c8 9a31f624b2f1c8d4 d3ef739e94f76ceb f98739566ebb7713 6384cf5436c30d89 7628a88b22719ecf 85a0d301c72ae598 cac125b5b23f254f 82e793cd9460447c f55b6ebc7e08c7bf 265ba36e379f861c 8ff5c5c19270c92b a0cee31e8852087b f480c446a09839fa

## Grouping (both ways; merger owns the gap unit)
- Per behavior gap: 3 - (a) page @title text unasserted across 6 controllers (15 mutants: inbox 2, domains title 4, reparents title 4, modmails 2, settings 2, search title 1); (b) @title_h1 duplicate-h1 suppression unasserted (4 mutants: a0cee31e8852087b, f480c446a09839fa, 7628a88b22719ecf, 6384cf5436c30d89); (c) search what-default title branch unpinned (3 mutants: 7a2eb67c33630d46, 721be5b96d2f1bf9, b3c29e6d9b83c93b).
- Per statement/span: 8 - inbox:17, domains:18, domains:19, reparents:6, reparents:7, modmails:5, settings:9, search:19
- Per mutant: 22

## Controls
- Probe iteration recorded: v1 R2/D2 asserted no h1 matching title text, but both views render their own hardcoded h1; v2 counts h1 tags (1 = view only; mutant yields 2). All receipts are v2; probe standalone-verified 9/0 on original before the driver.
- Original baseline: 48 examples, 0 failures (7 covering files + 9 probe examples)
- Per mutant: exact applied edit via scripted string replacement from packet spans; existing 7 covering files 39/0 (survival reproduced); probe failure exactly as tabled; git checkout revert 0 diff lines
- Restored control: final-restored.log 48/0; probe removed; git status app/ spec/ config/ clean

## Completeness limits
- Unit proofs cover the corrective covering set + probe only; all 22 survivors remain NOT existing-whole-suite-confirmed (snapshot pointer covers no edited lines).
- Producer-noted unmeasured subjects (Inbox#unread 36, Messages#index 9, Origins#edit 4 mutants): absent METHOD keys per producer claim, NOT verified line-unexecuted here; no coverage-gap claim made from absence.
- 14 kills (2 assertion + 12 crash) not re-gated, no anomaly.
