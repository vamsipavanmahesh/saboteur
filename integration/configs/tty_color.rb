# SPDX-License-Identifier: MIT
# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  # Harness contract: run each target's whole suite; the snapshot counts pin it.
  c.test_selection = :all
  c.exclude = ["lib/tty/color/version.rb"]
end
