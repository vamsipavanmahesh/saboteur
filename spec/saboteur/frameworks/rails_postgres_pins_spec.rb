# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The Postgres copy of a test database: the exact SQL, the maintenance
# connection it runs on, and the refusal that names the sessions blocking the
# template.
RSpec.describe Saboteur::Frameworks::Rails, "Postgres copy" do
  let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
  let(:sql) { [] }
  let(:db) { double("db", database: "app_test", configuration_hash: { adapter: "postgresql", host: "localhost" }) }

  def connection_with(sessions)
    statements = sql
    connection = Object.new
    connection.define_singleton_method(:quote_table_name) { |name| %("#{name}") }
    connection.define_singleton_method(:quote) { |value| "'#{value}'" }
    connection.define_singleton_method(:execute) { |statement| statements << statement }
    connection.define_singleton_method(:select_values) do |query|
      (statements << query.strip.gsub(/\s+/, " ")) && sessions
    end
    connection
  end

  describe "#copy_postgres" do
    it "drops any old copy, checks the template, then creates the copy from it" do
      allow(rails).to receive(:with_maintenance_connection).and_yield(connection_with([]))
      rails.send(:copy_postgres, db, "app_test_saboteur2")
      expect(sql).to eq([
                          %(DROP DATABASE IF EXISTS "app_test_saboteur2"),
                          "SELECT application_name FROM pg_stat_activity WHERE datname = 'app_test' " \
                          "AND pid <> pg_backend_pid()",
                          %(CREATE DATABASE "app_test_saboteur2" TEMPLATE "app_test")
                        ])
    end
  end

  describe "#drop_postgres" do
    it "drops the copy only if it exists" do
      allow(rails).to receive(:with_maintenance_connection).and_yield(connection_with([]))
      rails.send(:drop_postgres, db, "app_test_saboteur2")
      expect(sql).to eq([%(DROP DATABASE IF EXISTS "app_test_saboteur2")])
    end
  end

  describe "#refuse_busy_template" do
    it "names the other sessions, counting them and calling unnamed ones unnamed" do
      connection = connection_with(["psql", "", nil])
      expect { rails.send(:refuse_busy_template, connection, "app_test") }.to raise_error(
        Saboteur::Error,
        "cannot copy the test database app_test: 3 other session(s) connected (psql, unnamed, unnamed). " \
        "Stop other test runs, consoles or Spring, then run saboteur again."
      )
    end

    it "does nothing when nobody else is connected" do
      expect(rails.send(:refuse_busy_template, connection_with([]), "app_test")).to be_nil
    end
  end

  describe "#with_maintenance_connection" do
    it "connects a class of its own to the postgres database, yields its connection and removes it" do
      pool = double("pool")
      admin = double("admin", connection_pool: pool)
      allow(admin).to receive(:establish_connection)
      allow(admin).to receive(:remove_connection)
      allow(pool).to receive(:with_connection).and_yield(:conn)
      allow(rails).to receive(:maintenance_record).and_return(admin)
      yielded = nil
      rails.send(:with_maintenance_connection, db) { |connection| yielded = connection }
      expect(yielded).to eq(:conn)
      expect(admin).to have_received(:establish_connection)
        .with({ adapter: "postgresql", host: "localhost", database: "postgres" })
      expect(admin).to have_received(:remove_connection)
    end

    it "does not fail on cleanup when the maintenance class could not be built" do
      allow(rails).to receive(:maintenance_record).and_raise("no class")
      expect { rails.send(:with_maintenance_connection, db) { nil } }.to raise_error("no class")
    end
  end
end
