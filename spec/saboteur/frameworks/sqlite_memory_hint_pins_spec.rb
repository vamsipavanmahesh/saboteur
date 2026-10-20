# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Frameworks::SqliteMemoryDatabase do
  def memory_pool(connection: nil, error: nil, adapter: "sqlite3", database: ":memory:")
    config = double("db config", adapter: adapter, database: database)
    pool = double("pool", db_config: config)
    allow(pool).to receive(:with_connection) do |&block|
      raise error if error

      block.call(connection)
    end
    pool
  end

  def connection_with(tables)
    double("connection", select_values: tables)
  end

  describe ".fork_loss_hint" do
    before { stub_const("ActiveRecord::Base", double("ActiveRecord base")) }

    it "is no hint when listing the pools raises a StandardError" do
      allow(ActiveRecord::Base).to receive(:connection_handler).and_raise(StandardError, "boom")

      expect(described_class.fork_loss_hint).to be_nil
    end

    it "is no hint when listing the pools raises a ScriptError" do
      allow(ActiveRecord::Base).to receive(:connection_handler).and_raise(NotImplementedError, "boom")

      expect(described_class.fork_loss_hint).to be_nil
    end
  end

  describe ".unseeded_memory_database?" do
    it "is false when the pool cannot be queried" do
      pool = memory_pool(error: StandardError.new("closed"))

      expect(described_class.send(:unseeded_memory_database?, pool)).to be(false)
    end
  end

  describe ".user_tables" do
    it "drops sqlite_sequence, schema_migrations and ar_internal_metadata and keeps the rest" do
      connection = connection_with(%w[sqlite_sequence schema_migrations ar_internal_metadata roles])

      expect(described_class.send(:user_tables, connection)).to eq(%w[roles])
    end

    %w[sqlite_sequence ar_internal_metadata].each do |bookkeeping|
      it "treats a database holding only #{bookkeeping} as empty" do
        pool = memory_pool(connection: connection_with([bookkeeping]))

        expect(described_class.send(:empty_memory_database?, pool)).to be(true)
      end
    end
  end

  describe ".empty_memory_database?" do
    def empty?(**options)
      pool = memory_pool(connection: connection_with([]), **options)
      described_class.send(:empty_memory_database?, pool)
    end

    it "is true for an empty sqlite :memory: database" do
      expect(empty?).to be(true)
    end

    it "reads the adapter and database through to_s" do
      expect(empty?(adapter: :sqlite3, database: :":memory:")).to be(true)
    end

    it "is false for a sqlite file database" do
      expect(empty?(database: "db/test.sqlite3")).to be(false)
    end

    it "is false for another adapter, even with :memory: as the database" do
      expect(empty?(adapter: "postgresql")).to be(false)
    end

    it "is false when the adapter or the database is nil" do
      expect([empty?(adapter: nil), empty?(database: nil)]).to eq([false, false])
    end

    it "is false when the pool cannot be queried" do
      pool = memory_pool(error: StandardError.new("closed"))

      expect(described_class.send(:empty_memory_database?, pool)).to be(false)
    end
  end
end
