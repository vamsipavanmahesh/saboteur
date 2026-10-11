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
        @worker_copies = []
      end

      def before_boot
        env = ENV.fetch("RAILS_ENV", nil) || ENV.fetch("RACK_ENV", nil)
        raise Error, "rails integration refuses to run unless RAILS_ENV=test (got #{env.inspect})" unless env == "test"

        # libpq probes for Kerberos (GSS encryption) on every new connection;
        # on macOS that goes through XPC, which crashes a forked process. The
        # databases are local only (check_databases), so it buys nothing.
        ENV["PGGSSENCMODE"] ||= "disable"
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
      # others get copies named for saboteur, never a name parallel_tests or
      # a developer might already use.
      def self.worker_database(database, number)
        return database if number.zero?

        extension = File.extname(database)
        "#{database.delete_suffix(extension)}_saboteur#{number + 1}#{extension}"
      end

      # Parent, before workers start: one copy of each test database per
      # extra worker, made from the prepared test database. Only copies
      # that were actually made are tracked, so cleanup_workers drops
      # exactly those - including the partial set when a copy failed.
      def prepare_workers(jobs)
        return unless defined?(::ActiveRecord::Base) && jobs > 1

        @worker_copies = []
        test_configs.each do |db|
          (1...jobs).each do |number|
            name = self.class.worker_database(db.database, number)
            # Track the target before the copy, not after it: an attempt
            # that created the database and then failed (a post-CREATE
            # error, a partial SQLite copy) must still be dropped at the
            # end of the run. Dropping is idempotent (DROP IF EXISTS,
            # rm -f), so tracking a copy that never happened costs nothing.
            @worker_copies << [db, name]
            copy_database(db, name)
          end
        end
        disconnect
      end

      # Parent, after the run: drop every copy prepare_workers made, so runs
      # do not collect one database per worker. Every copy is attempted even
      # when a drop fails; the failures are reported together at the end.
      def cleanup_workers
        return if @worker_copies.empty?

        failures = @worker_copies.filter_map do |db, name|
          drop_database(db, name)
          nil
        rescue StandardError => e
          "#{name}: #{e.message}"
        end
        @worker_copies = []
        begin
          disconnect
        rescue StandardError => e
          failures << "disconnect: #{e.message}"
        end
        raise Error, "could not drop worker database copies: #{failures.join('; ')}" if failures.any?
      end

      # Worker: point every connection pool (primary, and any cache, queue or
      # connects_to databases, for every role and shard) at this worker's
      # copy of its database.
      def start_worker(number)
        return unless defined?(::ActiveRecord::Base) && number.positive?

        handler = ::ActiveRecord::Base.connection_handler
        handler.connection_pool_list(:all).to_a.each do |pool|
          config = pool.pool_config
          db = pool.db_config
          handler.establish_connection(db.configuration_hash.merge(database: self.class.worker_database(db.database,
                                                                                                        number)),
                                       owner_name: self.class.owner_of(config), role: config.role,
                                       shard: config.shard)
        end
      end

      def self.owner_of(pool_config)
        return pool_config.connection_class if pool_config.respond_to?(:connection_class)

        Object.const_get(pool_config.connection_descriptor.name)
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
          copy_postgres(db, name)
        when /sqlite/
          # A database in WAL mode keeps recent writes in -wal/-shm files.
          ["", "-wal", "-shm"].each do |suffix|
            FileUtils.cp("#{db.database}#{suffix}", "#{name}#{suffix}") if File.exist?("#{db.database}#{suffix}")
          end
        else
          raise Error, "--jobs > 1 with Rails needs Postgres or SQLite (got #{db.adapter})"
        end
      end

      # The mirror of copy_database. Adapters copy_database rejects never get
      # copies, so there is nothing to drop for them.
      def drop_database(db, name)
        case db.adapter
        when /postg/
          disconnect
          drop_postgres(db, name)
        when /sqlite/
          ["", "-wal", "-shm"].each { |suffix| FileUtils.rm_f("#{name}#{suffix}") }
        end
      end

      def copy_postgres(db, name)
        with_maintenance_connection(db) do |connection|
          connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(name)}")
          connection.execute("CREATE DATABASE #{connection.quote_table_name(name)} " \
                             "TEMPLATE #{connection.quote_table_name(db.database)}")
        end
      end

      def drop_postgres(db, name)
        with_maintenance_connection(db) do |connection|
          connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(name)}")
        end
      end

      # Through a connection class of saboteur's own, so the app's
      # connections never point at the maintenance database.
      def with_maintenance_connection(db, &)
        admin = maintenance_record
        admin.establish_connection(db.configuration_hash.merge(database: "postgres"))
        admin.connection_pool.with_connection(&)
      ensure
        admin&.remove_connection
      end

      # ActiveRecord names a connection's owner by class name, so the class
      # needs a constant.
      def maintenance_record
        return self.class::MaintenanceRecord if self.class.const_defined?(:MaintenanceRecord, false)

        self.class.const_set(:MaintenanceRecord, Class.new(::ActiveRecord::Base) { self.abstract_class = true })
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
