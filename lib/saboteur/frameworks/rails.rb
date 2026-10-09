# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

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

      # The database a worker uses: the first keeps the test database, the
      # others get numbered copies, as Rails parallel tests name them.
      def self.worker_database(database, number)
        return database if number.zero?

        extension = File.extname(database)
        "#{database.delete_suffix(extension)}#{number + 1}#{extension}"
      end

      # Parent, before workers start: one copy of each test database per
      # extra worker, made from the prepared test database.
      def prepare_workers(jobs)
        return unless defined?(::ActiveRecord::Base) && jobs > 1

        test_configs.each do |db|
          (1...jobs).each { |number| copy_database(db, self.class.worker_database(db.database, number)) }
        end
        disconnect
      end

      # Worker: connect to this worker's copy.
      def start_worker(number)
        return unless defined?(::ActiveRecord::Base) && number.positive?

        db = test_configs.first
        settings = db.configuration_hash.merge(database: self.class.worker_database(db.database, number))
        ::ActiveRecord::Base.establish_connection(settings)
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

      def test_configs
        ::ActiveRecord::Base.configurations.configs_for(env_name: "test")
      end

      # Postgres: CREATE DATABASE ... TEMPLATE (needs no open connections to
      # the template, so it runs from the maintenance database). SQLite: a
      # file copy. Other adapters are not supported for workers.
      def copy_database(db, name)
        case db.adapter
        when /postg/
          disconnect
          ::ActiveRecord::Base.establish_connection(db.configuration_hash.merge(database: "postgres"))
          connection = ::ActiveRecord::Base.connection
          connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(name)}")
          connection.execute("CREATE DATABASE #{connection.quote_table_name(name)} " \
                             "TEMPLATE #{connection.quote_table_name(db.database)}")
        when /sqlite/
          FileUtils.cp(db.database, name)
        else
          raise Error, "--jobs > 1 with Rails needs Postgres or SQLite (got #{db.adapter})"
        end
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
