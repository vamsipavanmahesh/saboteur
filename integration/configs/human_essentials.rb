# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# rubyforgood/human-essentials at d6f8290 (MIT). Rails 8.1, Postgres.
Saboteur.configure do |c|
  c.rails = true
  c.include = ["app/models/**/*.rb", "app/services/**/*.rb"]
  # Harness contract: run each target's whole suite; the snapshot counts pin it.
  c.test_selection = :all
  # System specs drive headless Chrome; they are left out for the benchmark.
  c.rspec_args = ["--exclude-pattern", "spec/system/**/*_spec.rb", "spec"]
end
