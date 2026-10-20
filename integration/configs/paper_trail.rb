# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The target's models specs run in process against sqlite, whose test database
# lives under spec/dummy_app/db (integration/patches/paper_trail.patch).
Saboteur.configure do |c|
  c.include = %w[
    lib/paper_trail/record_trail.rb
    lib/paper_trail/has_paper_trail.rb
    lib/paper_trail/version_concern.rb
  ]
  c.tests = %w[spec/models]
  c.jobs = 1
  c.baseline_passes = 1
  c.coverage_recorder = ENV.fetch("SABOTEUR_COVERAGE_RECORDER", "coverage")
  c.sandbox_writable = %w[spec/dummy_app/db]
end
