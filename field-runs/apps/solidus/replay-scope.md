# Solidus narrowed replay scope (per "suite OR the directories you'll use")

The full core baseline (315 spec files) is already running and is preserved as the whole-suite actual.
For saboteur PR replays, the relevant spec scope derived from the 5 selected PRs' own diffs (every PR touches both source and its specs):

- PR 6691: core/app/models/spree/stock/availability_validator.rb -> core/spec/models/spree/stock/availability_validator_spec.rb
- PR 6677: core/lib/tasks/payment_method.rake -> core/spec/helpers/base_helper_spec.rb (note: source is a rake task; spec link is via helper spec - the PR's own spec change)
- PR 6697: core/app/models/spree/order_cancellations.rb + unit_cancel.rb -> core/spec/models/spree/order_cancellations_spec.rb + unit_cancel_spec.rb
- PR 6701: core/app/models/spree/payment_method/bogus_credit_card.rb -> core/spec/models/spree/payment_method/bogus_credit_card_spec.rb
- PR 6692: core/app/models/spree/stock/estimator.rb + shipping_rate_filter.rb + core/lib/spree/app_configuration.rb -> core/spec/models/spree/stock/{estimator,shipping_rate_filter}_spec.rb

Narrowed baseline-equivalent command (for any scoped reruns; NOT replacing the full baseline):
  cd core && bundle exec rspec spec/models/spree/stock spec/models/spree/order_cancellations_spec.rb spec/models/spree/unit_cancel_spec.rb spec/models/spree/payment_method/bogus_credit_card_spec.rb spec/helpers/base_helper_spec.rb

Exclusion rule stays: only specs red before saboteur runs, each with its reason, from logs/baseline-rspec.json.
