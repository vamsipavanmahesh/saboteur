# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The config `saboteur init` writes for a plain RSpec project.
  module StarterConfig
    TEXT = <<~RUBY
      # saboteur configuration. CLI flags override this file; every key not set
      # here keeps its default.
      Saboteur.configure do |c|
        c.integration = "rspec"
        c.include = ["lib/**/*.rb"]
        # Starter score gate; raise it as survivors are killed.
        c.threshold = 60
        # Survivors accepted with a reason live here:
        # c.ignore_file = "config/saboteur_ignore.rb"
      end
    RUBY
  end
end
