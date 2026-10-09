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

      # Watches for the app's SimpleCov and turns its start into a no-op the
      # moment the constant is defined, before any line of the app's
      # SimpleCov setup runs. saboteur does not load SimpleCov itself:
      # loading it runs the app's .simplecov at once.
      module SimpleCovWatch
        def const_added(name)
          super
          Boot.silence_simplecov if name == :SimpleCov && equal?(Object)
        end
      end

      def self.watch_for_simplecov
        Object.singleton_class.prepend(SimpleCovWatch) unless Object.singleton_class.include?(SimpleCovWatch)
        silence_simplecov if defined?(::SimpleCov)
      end

      def self.silence_simplecov
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
        self.class.watch_for_simplecov
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
