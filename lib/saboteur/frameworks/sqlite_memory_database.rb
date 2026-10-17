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
               "a before(:suite) hook, or in an after_fork hook (config/saboteur_hooks.rb via c.hooks)"

      module_function

      # The remedy text when a current pool points at an empty sqlite
      # :memory: database, else nil. Diagnostic only: any error is no hint,
      # never a failure of the run itself.
      def fork_loss_hint
        return unless defined?(ActiveRecord::Base)

        pools = ActiveRecord::Base.connection_handler.connection_pool_list
        pools.any? { |pool| empty_memory_database?(pool) } ? REMEDY : nil
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

      # Migration bookkeeping is not user schema: a database with only these
      # tables still has no schema for the suite's models.
      def user_tables(connection)
        connection.select_values("SELECT name FROM sqlite_master WHERE type = 'table'") -
          %w[sqlite_sequence schema_migrations ar_internal_metadata]
      end
    end
  end
end
