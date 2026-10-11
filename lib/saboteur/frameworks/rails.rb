# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "fileutils"
require "pathname"

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

      # How many blocking session names the template-copy error lists.
      MAX_BLOCKER_NAMES = 5

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

        # Bytecode from Bootsnap's compile cache carries no coverage counters,
        # so a file served from the cache never appears in Coverage.result.
        # Turn the cache off for this process before config/boot loads
        # Bootsnap; the load-path cache still works. Bootsnap checks
        # DISABLE_<feature> by presence, so a value the user set disables the
        # cache too. Files loaded during the eager load are also covered by
        # eager_load_with_coverage_running.
        ENV["DISABLE_BOOTSNAP_COMPILE_CACHE"] ||= "1"
      end

      def after_boot
        unless defined?(::Rails.env)
          raise Error,
                "rails: true but Rails did not load (add config/environment to require - for an engine, " \
                "its dummy app's environment, such as test/dummy/config/environment.rb; only a dynamically " \
                "created dummy app has no environment file, and there you require the helper that calls " \
                "setup instead, such as DummyApp.setup in spec/rails_helper)"
        end
        raise Error, "rails integration refuses to run: Rails.env is #{::Rails.env}" unless ::Rails.env.test?

        check_databases
        eager_load_with_coverage_running
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
      # extra worker, made from the prepared test database. Every attempted
      # copy is tracked before it runs, so cleanup_workers drops them all,
      # including the partial set when a copy failed.
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

      # Bootsnap before 1.25 skips its bytecode cache only while Coverage is
      # running (1.25 and later skip it whenever Coverage is set up, suspended
      # or not), and Coverage is suspended while the app boots (exe/saboteur
      # sets it up suspended). Cached bytecode carries no coverage counters.
      # Resume Coverage just for the eager load, so every app file compiles
      # with counters. The coverage recorder clears the counts before the
      # suite runs, so load-time hits are never credited to a test.
      def eager_load_with_coverage_running
        return ::Rails.application.eager_load! unless Coverage.state == :suspended

        Coverage.resume
        begin
          ::Rails.application.eager_load!
        ensure
          Coverage.suspend
        end
      end

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
          copy_sqlite(db, name)
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
          target = sqlite_absolute(name)
          ["", "-wal", "-shm"].each { |suffix| FileUtils.rm_f("#{target}#{suffix}") }
        end
      end

      # A relative sqlite path means something only to Rails: 7.1+ resolves
      # it against Rails.root, not the process working directory. Resolve
      # the source the same way, checkpoint so a live WAL database holds
      # every committed write in its main file, then snapshot it through
      # the backup API. A missing source is an error, not a skip: otherwise
      # the worker starts from a fresh empty database and silently tests
      # nothing.
      def copy_sqlite(db, name)
        source = sqlite_absolute(db.database)
        unless File.exist?(source)
          raise Error, "test database #{source} does not exist; run the test suite once to create it"
        end

        checkpoint_sqlite(source)
        backup_sqlite(source, sqlite_absolute(name))
      end

      def sqlite_absolute(database)
        return database if Pathname.new(database).absolute?
        return database unless defined?(::Rails)

        File.expand_path(database, ::Rails.root)
      end

      # wal_checkpoint(TRUNCATE) reports instead of raising: [busy, frames
      # in the WAL, frames checkpointed]. A busy reader or an incomplete
      # pass leaves committed writes outside the main file, and copying on
      # would silently miss them - fail closed instead. Through a
      # connection of saboteur's own, so the app's connections never point
      # at the database being checkpointed.
      def checkpoint_sqlite(source)
        with_sqlite(source) do |database|
          busy, frames, checkpointed = database.execute("PRAGMA wal_checkpoint(TRUNCATE)").first
          return if busy.zero? && frames == checkpointed

          raise Error, "could not checkpoint #{source} before copying it " \
                       "(busy: #{busy}, frames: #{frames}, checkpointed: #{checkpointed}); " \
                       "close the connections holding it and run again"
        end
      end

      # A byte copy of main + WAL + SHM is no snapshot: a write landing
      # between the file copies leaves the set malformed. The backup API
      # copies a consistent image and restarts when the source changes
      # under it. The target starts clean so stale sidecars from an
      # earlier byte copy cannot shadow the fresh image.
      def backup_sqlite(source, target)
        ["", "-wal", "-shm"].each { |suffix| FileUtils.rm_f("#{target}#{suffix}") }
        with_sqlite(source, readonly: true) do |src|
          with_sqlite(target) do |dst|
            backup = SQLite3::Backup.new(dst, "main", src, "main")
            begin
              backup.step(-1)
            ensure
              backup.finish
            end
          end
        end
      end

      def with_sqlite(path, **)
        require "sqlite3"

        database = SQLite3::Database.new(path, **)
        begin
          yield database
        ensure
          database.close
        end
      end

      # Through a connection class of saboteur's own, so the app's
      # connections never point at the maintenance database.
      def copy_postgres(db, name)
        with_maintenance_connection(db) do |connection|
          connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(name)}")
          refuse_busy_template(connection, db.database)
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

      # Postgres refuses CREATE DATABASE ... TEMPLATE while any other session
      # is connected to the template, so name the blockers instead of dying
      # mid-run with the raw error. Never terminates other sessions.
      def refuse_busy_template(connection, database)
        blockers = connection.select_values(<<~SQL)
          SELECT application_name FROM pg_stat_activity
          WHERE datname = #{connection.quote(database)} AND pid <> pg_backend_pid()
        SQL
        return if blockers.empty?

        names = blockers.map { |app| app.to_s.empty? ? "unnamed" : app }.first(MAX_BLOCKER_NAMES)
        raise Error, "cannot copy the test database #{database}: #{blockers.size} other session(s) connected " \
                     "(#{names.join(', ')})#{', ...' if blockers.size > names.size}. " \
                     "Stop other test runs, consoles or Spring, then run saboteur again."
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
