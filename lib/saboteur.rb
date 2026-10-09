# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "saboteur/version"

module Saboteur
  class Error < StandardError; end

  # Invalid configuration or input files (exit code 2).
  class ConfigError < Error; end

  class << self
    # Set while hook files from config load, so they can call Saboteur.hook.
    attr_accessor :current_hooks

    # Registers a lifecycle hook from a hooks file:
    #
    #   Saboteur.hook(:after_fork) { Redis.current.disconnect! }
    #   Saboteur.hook(:around_mutant) { |mutation, run| Timecop.freeze { run.call } }
    def hook(name, callable = nil, &)
      raise Error, "Saboteur.hook is only available while hook files load" unless current_hooks

      current_hooks.register(name, callable, &)
    end
  end
end

require_relative "saboteur/hooks"
require_relative "saboteur/mutation_source/base"
require_relative "saboteur/mutation_source/builtin"
require_relative "saboteur/integration/base"
require_relative "saboteur/subject"
require_relative "saboteur/subject_finder"
require_relative "saboteur/reevaluator"
require_relative "saboteur/coverage_map"
require_relative "saboteur/supervisor"
require_relative "saboteur/runner"
require_relative "saboteur/result"
require_relative "saboteur/diff"
require_relative "saboteur/config"
require_relative "saboteur/ignore_list"
require_relative "saboteur/git_diff"
require_relative "saboteur/rails"
require_relative "saboteur/reporter/terminal"
require_relative "saboteur/reporter/stryker"
require_relative "saboteur/engine"
