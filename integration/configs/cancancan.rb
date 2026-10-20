# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# cancancan's specs run in process against an in-memory sqlite database
# (DB=sqlite in targets.yml); the whole suite runs in seconds.
Saboteur.configure do |c|
  c.include = %w[
    lib/cancan/ability.rb
    lib/cancan/rule.rb
    lib/cancan/conditions_matcher.rb
    lib/cancan/model_adapters/conditions_extractor.rb
  ]
  c.tests = %w[spec]
  c.jobs = 1
  c.baseline_passes = 1
  c.coverage_recorder = ENV.fetch("SABOTEUR_COVERAGE_RECORDER", "coverage")
end
