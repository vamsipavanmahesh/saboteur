# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Frameworks
    # The #387 shape: a suite connects ActiveRecord to a sqlite ":memory:"
    # database and loads its schema at require time. Every saboteur child is
    # a fork, ActiveRecord's fork-safe pool reconnects there, and a fresh
    # in-memory database is EMPTY - the schema is gone, and every example
    # fails with "Could not find table" while plain rspec stays green. A
    # child that detects the shape says so and names the remedies instead of
    # sending the user debugging a healthy suite.
    module SqliteMemoryDatabase
      REMEDY = "a sqlite :memory: database is empty in this forked child: in-memory databases do not " \
               "survive saboteur's fork, so a schema loaded at require time is lost. Load the schema in " \
               "a before(:suite) hook, or in an after_fork hook in config/saboteur_hooks.rb; wire it in " \
               'config/saboteur.rb with c.hooks = ["config/saboteur_hooks.rb"]'

      # The #594 seed variant: the suite moved its schema into a hook (the
      # schema remedy above), so children get tables - but rows seeded at
      # require time (rolify's spec/support/data.rb) lived in the parent's
      # database and are lost across the fork all the same.
      SEED_REMEDY = "a sqlite :memory: database in this forked child has its schema but no rows: rows seeded at " \
                    "require time (seed data, fixtures loaded at boot) are lost across saboteur's fork, just like " \
                    "the schema. Seed in a before(:suite) hook, or in an after_fork hook in " \
                    "config/saboteur_hooks.rb; wire it in config/saboteur.rb with " \
                    'c.hooks = ["config/saboteur_hooks.rb"]'

      module_function

      # The remedy text when a current pool points at an empty sqlite
      # :memory: database, else nil. Diagnostic only: any error is no hint,
      # never a failure of the run itself.
      def fork_loss_hint
        return unless defined?(ActiveRecord::Base)

        pools = ActiveRecord::Base.connection_handler.connection_pool_list
        return REMEDY if pools.any? { |pool| empty_memory_database?(pool) }
        return SEED_REMEDY if pools.any? { |pool| unseeded_memory_database?(pool) }

        nil
      rescue StandardError, ScriptError
        nil
      end

      def empty_memory_database?(pool)
        config = pool.db_config
        return false unless config.adapter.to_s == "sqlite3" && config.database.to_s == ":memory:"

        pool.with_connection { |connection| user_tables(connection).empty? }
      rescue StandardError
        false
      end

      # Schema but not a single row anywhere: the hook-loaded schema
      # survived the fork, the require-time seeds did not (#594).
      def unseeded_memory_database?(pool)
        config = pool.db_config
        return false unless config.adapter.to_s == "sqlite3" && config.database.to_s == ":memory:"

        pool.with_connection do |connection|
          tables = user_tables(connection)
          tables.any? && tables.all? do |table|
            connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} LIMIT 1").nil?
          end
        end
      rescue StandardError
        false
      end

      # Migration bookkeeping is not user schema: a database with only these
      # tables still has no schema for the suite's models.
      def user_tables(connection)
        connection.select_values("SELECT name FROM sqlite_master WHERE type = 'table'") -
          %w[sqlite_sequence schema_migrations ar_internal_metadata]
      end
    end
  end
end
