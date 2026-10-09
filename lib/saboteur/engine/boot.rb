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

      # Prepended to SimpleCov's singleton: saboteur needs Ruby's Coverage for
      # its own map, and Coverage can only be set up once per process.
      module SimpleCovOff
        def start(*, **)
          nil
        end
      end

      # Loads the app's SimpleCov (if it has one) before the app does, so the
      # app's own SimpleCov.start becomes a no-op instead of a boot failure.
      def self.silence_simplecov
        unless defined?(::SimpleCov)
          begin
            require "simplecov"
          rescue LoadError
            return
          end
        end
        return if ::SimpleCov.singleton_class.include?(SimpleCovOff)

        ::SimpleCov.singleton_class.prepend(SimpleCovOff)
        warn "saboteur: SimpleCov.start ignored for this run (saboteur needs Ruby's Coverage itself)"
      end

      # The Rails profile when rails: true, else nil (set by load_target).
      attr_reader :rails

      def initialize(config, hooks)
        @config = config
        @hooks = hooks
        @root = File.realpath(config.root)
      end

      def load_target
        self.class.silence_simplecov
        load_hooks
        @rails = rails = Frameworks::Rails.new(@config, @hooks) if @config["rails"]
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
