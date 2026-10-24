# HE Aug-30 snapshot union - tree drift evidence (API compare 46420673...2857b48f, fetched 2026-10-24 11:34 IST)

status: ahead, ahead_by: 37 commits

| file | status | + | - |
| --- | --- | --- | --- |
| app/controllers/items_controller.rb | modified | 8 | 3 |
| app/controllers/partners/requests_controller.rb | modified | 4 | 1 |
| app/controllers/reports/annual_reports_controller.rb | modified | 48 | 1 |
| app/models/concrete_item.rb | modified | 1 | 0 |
| app/models/item.rb | modified | 6 | 3 |
| app/models/item_unit.rb | modified | 6 | 5 |
| app/models/kit.rb | modified | 1 | 0 |
| app/models/partners/item_request.rb | modified | 7 | 3 |
| app/models/request.rb | modified | 1 | 1 |
| app/services/exports/export_report_csv_service.rb | modified | 24 | 2 |
| app/services/partners/request_create_service.rb | modified | 25 | 4 |
| app/views/items/_form.html.erb | modified | 33 | 1 |
| app/views/partners/individuals_requests/new.html.erb | modified | 19 | 18 |
| app/views/partners/requests/new.html.erb | modified | 0 | 5 |
| app/views/reports/annual_reports/index.html.erb | modified | 11 | 0 |
| app/views/transfers/_transfer_row.html.erb | modified | 1 | 1 |
| config/routes.rb | modified | 5 | 0 |
| db/migrate/20250912155420_add_request_limit_to_item_unit.rb | added | 6 | 0 |
| db/schema.rb | modified | 2 | 0 |
| docs/user_guide/bank/images/reports/reports-anual-survey-yearly-export.png | added | 0 | 0 |
| docs/user_guide/bank/reports_annual_survey.md | modified | 18 | 9 |
| spec/controllers/items_controller_spec.rb | modified | 70 | 32 |
| spec/factories/item_units.rb | modified | 6 | 5 |
| spec/factories/items.rb | modified | 1 | 0 |
| spec/factories/kits.rb | modified | 1 | 0 |
| spec/factories/organizations.rb | modified | 6 | 0 |
| spec/models/item_spec.rb | modified | 4 | 3 |
| spec/models/item_unit_spec.rb | modified | 6 | 5 |
| spec/models/kit_spec.rb | modified | 1 | 0 |
| spec/models/partners/item_request_spec.rb | modified | 6 | 2 |
| spec/models/request_spec.rb | modified | 1 | 1 |
| spec/requests/items_requests_spec.rb | modified | 1 | 1 |
| spec/requests/partners/requests_spec.rb | modified | 25 | 10 |
| spec/requests/reports/annual_reports_requests_spec.rb | modified | 85 | 1 |
| spec/requests/transfers_request_spec.rb | added | 35 | 0 |
| spec/services/exports/export_report_csv_service_spec.rb | modified | 46 | 0 |
| spec/services/partners/request_create_service_spec.rb | modified | 11 | 1 |
| spec/system/partners/requests_system_spec.rb | modified | 1 | 1 |
| spec/system/transfer_system_spec.rb | modified | 2 | 2 |
