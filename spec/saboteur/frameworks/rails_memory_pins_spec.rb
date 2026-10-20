# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "sqlite3"

# The connection-pool walks (always every role and shard), the memoized
# maintenance class, the reconnect order, the snapshot file name and the
# bounded backup retries.
RSpec.describe Saboteur::Frameworks::Rails, "pools and snapshots" do
  let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

  after do
    described_class.send(:remove_const, :MaintenanceRecord) if described_class.const_defined?(:MaintenanceRecord, false)
  end

  def strict_base(pools)
    handler = double("handler")
    allow(handler).to receive(:connection_pool_list).with(:all).and_return(pools)
    double("ActiveRecord::Base", connection_handler: handler)
  end

  describe "#maintenance_record" do
    it "builds one abstract class and hands the same one back" do
      base = Class.new { class << self; attr_accessor :abstract_class; end }
      stub_const("ActiveRecord::Base", base)
      first = rails.send(:maintenance_record)
      expect(first.superclass).to eq(base)
      expect(first.abstract_class).to be(true)
      expect(described_class.const_defined?(:MaintenanceRecord, false)).to be(true)
      expect(rails.send(:maintenance_record)).to equal(first)
    end
  end

  describe "#maintenance_record with an unrelated top-level constant" do
    it "ignores an inherited MaintenanceRecord and builds its own" do
      base = Class.new { class << self; attr_accessor :abstract_class; end }
      stub_const("ActiveRecord::Base", base)
      stub_const("MaintenanceRecord", Class.new)
      own = rails.send(:maintenance_record)
      expect(own.superclass).to eq(base)
      expect(own).not_to equal(MaintenanceRecord)
    end
  end

  describe "#reconnect" do
    it "disconnects first and then restores the memory databases" do
      allow(rails).to receive(:disconnect)
      allow(rails).to receive(:restore_memory_databases)
      rails.send(:reconnect)
      expect(rails).to have_received(:disconnect).ordered
      expect(rails).to have_received(:restore_memory_databases).ordered
    end
  end

  describe "#disconnect" do
    it "asks for the pools of every role and shard when disconnecting" do
      stub_const("ActiveRecord::Base", strict_base([]))
      expect { rails.send(:disconnect) }.not_to raise_error
    end
  end

  describe "#restore_memory_databases" do
    it "asks for the pools of every role and shard when restoring" do
      stub_const("ActiveRecord::Base", strict_base([]))
      rails.instance_variable_set(:@memory_snapshots, { cfg: "/snap/0.sqlite3" })
      expect { rails.send(:restore_memory_databases) }.not_to raise_error
    end
  end

  describe "#snapshot_memory_databases" do
    it "writes each in-memory database to its own numbered file in a saboteur temp dir" do
      config = double("config", adapter: "sqlite3", database: ":memory:")
      pool = double("pool", db_config: config)
      raw = double("raw")
      allow(pool).to receive(:with_connection).and_yield(double("connection", raw_connection: raw))
      stub_const("ActiveRecord::Base", strict_base([pool]))
      allow(rails).to receive(:own_memory_snapshots)
      allow(SQLite3::Database).to receive(:new).and_return(:file)
      allow(rails).to receive(:with_backup).and_yield(:backup)
      allow(rails).to receive(:step_backup)
      rails.send(:snapshot_memory_databases)
      dir = rails.instance_variable_get(:@memory_snapshot_dir)
      expect(File.basename(dir)).to start_with("saboteur-memory-")
      expect(SQLite3::Database).to have_received(:new).with(File.join(dir, "0.sqlite3"))
      expect(rails).to have_received(:step_backup).with(:backup, File.join(dir, "0.sqlite3"))
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  describe "#step_backup" do
    it "tries a busy backup exactly the bounded number of times" do
      backup = instance_double(SQLite3::Backup)
      allow(backup).to receive(:step).and_return(described_class::SQLITE_BUSY)
      allow(rails).to receive(:sleep)
      expect { rails.send(:step_backup, backup, "t") }.to raise_error(Saboteur::Error, /still busy/)
      expect(backup).to have_received(:step).exactly(described_class::BACKUP_ATTEMPTS).times
      expect(described_class::BACKUP_ATTEMPTS).to eq(5)
    end
  end
end
