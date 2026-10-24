# Out-of-scope changed production Ruby files - lobsters selected 15 (2026-10-24)

Rule: mutation scope = app/ and lib/ production Ruby. A changed .rb file outside spec/, test/, db/, config/ that is not under app/ or lib/ is recorded as OUT OF SCOPE (changed production code the mutation run cannot mutate). Source: GitHub API pulls/<N>/files, fetched 2026-10-24 ~11:23 IST, per_page=100 (no pagination flags). Independently re-fetched by the merger lane; matches the producer's scan claim.

| PR | production Ruby changed | out of scope |
| --- | --- | --- |
| 2231 | app/models/comment.rb | none |
| 2204 | app/models/story.rb | none |
| 2157 | app/controllers/stories_controller.rb, extras/routes.rb | extras/routes.rb |
| 2156 | app/controllers/settings_controller.rb | none |
| 2171 | app/helpers/users_helper.rb | none |
| 2172 | app/helpers/traffic_helper.rb, app/models/keystore.rb, app/models/story.rb, app/models/user.rb, app/models/vote.rb, extras/github.rb | extras/github.rb |
| 2183 | app/helpers/traffic_helper.rb | none |
| 2197 | 8 controllers (inbox, messages, mod/domains, mod/origins, mod/reparents, mod_mails, search, settings) | none |
| 2182 | app/models/story.rb, app/models/user.rb | none |
| 2175 | app/models/comment.rb | none |
| 2103 | app/helpers/application_helper.rb, app/helpers/traffic_helper.rb | none |
| 2205 | app/models/story.rb | none |
| 2174 | app/models/flagged_commenters.rb | none |
| 2178 | app/models/concerns/token.rb | none |
| 2158 | app/models/comment.rb | none |

Notes:
- PR 2157's extras/routes.rb change (story_image_or_logo_url routing logic) is outside the mutation scope: the row's mutants cover only app/controllers/stories_controller.rb. Recorded as a field-run instance of the out-of-scope changed-file class (user review 2026-10-24 11:21).
- PR 2172 (not yet executed) carries extras/github.rb out of scope; its row will cover only the five app/ files.
- PR 2196 is not in the selected 15 (CSS-only change, no app/lib Ruby).
