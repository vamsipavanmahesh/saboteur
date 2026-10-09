# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Frameworks
    # Opt-in Rails support (`rails: true` in .saboteur.yml).
    #
    # Refuses to run unless RAILS_ENV is test and every configured database is
    # local, eager loads the app so every subject's owner is defined before
    # forking, and drops database connections in the parent so each child opens
    # its own. Prints host names only, never credentials.
    class Rails
      LOCAL_HOSTS = ["localhost", "127.0.0.1", "::1", "[::1]"].freeze

      def initialize(config, hooks)
        @config = config
        @hooks = hooks
      end

      def before_boot
        env = ENV.fetch("RAILS_ENV", nil) || ENV.fetch("RACK_ENV", nil)
        raise Error, "rails integration refuses to run unless RAILS_ENV=test (got #{env.inspect})" unless env == "test"

        # Minitest's parallel executor would fork its own workers inside children.
        ENV["PARALLEL_WORKERS"] = "1"
      end

      def after_boot
        unless defined?(::Rails.env)
          raise Error,
                "rails: true but Rails did not load (add config/environment to require)"
        end
        raise Error, "rails integration refuses to run: Rails.env is #{::Rails.env}" unless ::Rails.env.test?

        check_databases
        ::Rails.application.eager_load!
        disconnect
        @hooks.register(:before_fork) { |_mutation| disconnect }
        @hooks.register(:after_fork) { reconnect }
      end

      def self.local_host?(host)
        host.nil? || host.to_s.empty? || host.to_s.start_with?("/") || LOCAL_HOSTS.include?(host.to_s.downcase)
      end

      private

      def check_databases
        return unless defined?(::ActiveRecord::Base)

        remote = ::ActiveRecord::Base.configurations.configs_for(env_name: "test").filter_map do |db|
          host = db.configuration_hash[:host]
          "#{db.name} (host #{host})" unless self.class.local_host?(host)
        end
        return if remote.empty?

        raise Error, "rails integration refuses to run against non-local databases: #{remote.join(', ')}"
      end

      def disconnect
        return unless defined?(::ActiveRecord::Base)

        ::ActiveRecord::Base.connection_handler.connection_pool_list(:all).each(&:disconnect!)
      end

      # The parent disconnected before fork, so inherited pools hold no sockets.
      # Disconnecting again in the child is idempotent and guarantees the child
      # checks out a fresh connection of its own on first use.
      def reconnect
        disconnect
      end
    end
  end
end
