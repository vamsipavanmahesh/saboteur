# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Loads the target once in the parent: hook files, the optional Rails
    # profile, configured boot files, then the test adapter (which loads the
    # test files without running any test). Returns the ready adapter.
    class Boot
      # A test suite that (perhaps only under a mutant) starts a saboteur run
      # would otherwise run saboteur inside a saboteur child, recursively.
      def self.refuse_recursion!
        return unless ENV[Execution::Supervisor::CHILD_ENV]

        raise Error, "refusing to start: this process is a saboteur child " \
                     "(#{Execution::Supervisor::CHILD_ENV} is set). A test is running saboteur itself; stub it."
      end

      def initialize(config, hooks)
        @config = config
        @hooks = hooks
        @root = File.realpath(config.root)
      end

      def load_target
        load_hooks
        rails = Frameworks::Rails.new(@config, @hooks) if @config["rails"]
        rails&.before_boot
        @hooks.run(:before_boot)
        @config["require"].each { |file| require File.expand_path(file, @root) }
        integration = Integration.fetch(@config["integration"]).new(@config)
        integration.setup
        rails&.after_boot
        @hooks.run(:after_boot)
        integration
      end

      private

      def load_hooks
        Saboteur.current_hooks = @hooks
        @config["hooks"].each { |file| load File.expand_path(file, @root) }
      ensure
        Saboteur.current_hooks = nil
      end
    end
  end
end
