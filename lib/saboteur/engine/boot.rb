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
        if ENV[Execution::ExternalRunner::CHILD_MARKER]
          raise Error, "refusing to start: this process runs inside a saboteur external test command " \
                       "(#{Execution::ExternalRunner::CHILD_MARKER} is set); a nested run could race its tree"
        end
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
        warn "saboteur: SimpleCov.start ignored for this run (saboteur needs Ruby's Coverage itself)\n  " \
             "Fix: start SimpleCov only when saboteur is not driving the suite"
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
        add_spec_to_load_path
        # Helpers may configure RSpec before the integration loads specs.
        Integration::RSpec.new(@config).require_framework if @config["integration"] == "rspec"
        @config["require"].each { |file| require File.expand_path(file, @root) }
        integration = Integration.fetch(@config["integration"]).new(@config)
        # Running outside the bundle or beside an Appraisal gemfile set
        # loads the wrong gems; say so before the spec load fails in
        # confusing ways (#598, #609). Advisory only.
        EnvironmentHints.all(@root).each { |hint| warn "saboteur: warning: #{hint}" }
        integration.setup
        rails&.after_boot
        @hooks.run(:after_boot)
        integration
      end

      private

      # rspec puts spec/ on the load path, so a boot file under spec/ (a
      # dummy app's rails_helper, or a non-Rails gem's spec_helper that
      # requires its siblings) can require its siblings. Match that for
      # every project - a non-Rails gem does not add spec/ itself (#615) -
      # or the same require list fails to load.
      def add_spec_to_load_path
        path = File.join(@root, "spec")
        $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
      end

      def load_hooks
        Saboteur.current_hooks = @hooks
        @config["hooks"].each { |file| load hook_path(file) }
      ensure
        Saboteur.current_hooks = nil
      end

      # Kernel#load does not append .rb the way Kernel#require does, and
      # doctor accepts the extensionless form (#257), so resolve it the same
      # way here: the exact path first, then path.rb.
      def hook_path(file)
        path = File.expand_path(file, @root)
        rb = "#{path}.rb"
        return rb if !File.exist?(path) && File.extname(path).empty? && File.file?(rb)

        path
      end
    end
  end
end
