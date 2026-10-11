# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "pathname"
require "sqlite3"
require "tmpdir"

RSpec.describe Saboteur::Frameworks::Rails do
  describe ".worker_database" do
    # Names of their own, so a developer's parallel_tests databases
    # (app_test2, ...) are never dropped or overwritten.
    it "keeps the first worker on the test database and gives the rest saboteur copies" do
      expect((0..2).map { |n| described_class.worker_database("app_test", n) })
        .to eq(%w[app_test app_test_saboteur2 app_test_saboteur3])
    end

    it "names SQLite copies before their extension" do
      expect(described_class.worker_database("db/test.sqlite3", 1)).to eq("db/test_saboteur2.sqlite3")
    end
  end

  # The class that owns a connection pool, so the worker can point that
  # class at its own database copy.
  describe ".owner_of" do
    it "reads the connection descriptor (Rails 7.2 and later)" do
      descriptor = Struct.new(:name).new("String")
      expect(described_class.owner_of(Struct.new(:connection_descriptor).new(descriptor))).to eq(String)
    end

    it "reads the connection class (Rails 7.1)" do
      expect(described_class.owner_of(Struct.new(:connection_class).new(Integer))).to eq(Integer)
    end
  end

  # Fakes for the parts of ActiveRecord the worker setup touches.
  def fake_pool(role, database: "app_test", adapter: "postgresql")
    config = Struct.new(:connection_descriptor, :role, :shard)
                   .new(Struct.new(:name).new("ActiveRecord::Base"), role, :default)
    db = Struct.new(:database, :configuration_hash, :adapter)
               .new(database, { adapter: adapter, database: database }, adapter)
    Struct.new(:pool_config, :db_config).new(config, db)
  end

  describe "#start_worker" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
    let(:handler) { double("handler", connection_pool_list: [fake_pool(:writing), fake_pool(:reading)]) }

    # An app with `connects_to database: { writing: :primary, reading: :primary }`
    # has a pool per role; each must move, or reads share the main database
    # across workers.
    it "points the pool of every role at the worker's copy" do
      base = double("ActiveRecord::Base", connection_handler: handler)
      stub_const("ActiveRecord::Base", base)
      allow(handler).to receive(:establish_connection)
      rails.start_worker(1)
      %i[writing reading].each do |role|
        expect(handler).to have_received(:establish_connection)
          .with({ adapter: "postgresql", database: "app_test_saboteur2" }, owner_name: base, role: role,
                                                                           shard: :default)
      end
    end

    # Re-establishing an in-memory sqlite pool would discard the database;
    # the worker keeps the connection it inherited through fork.
    it "keeps in-memory sqlite pools on the inherited connection" do
      handler = double("handler",
                       connection_pool_list: [fake_pool(:writing, database: ":memory:", adapter: "sqlite3")])
      stub_const("ActiveRecord::Base", double("ActiveRecord::Base", connection_handler: handler))
      allow(handler).to receive(:establish_connection)
      rails.start_worker(1)
      expect(handler).not_to have_received(:establish_connection)
    end

    it "leaves worker 0 on the test database" do
      stub_const("ActiveRecord::Base", double("ActiveRecord::Base", connection_handler: handler))
      rails.start_worker(0)
      expect(handler).not_to have_received(:connection_pool_list)
    end
  end

  describe "#prepare_workers" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
    let(:log) { [] }

    after do
      described_class.send(:remove_const, :MaintenanceRecord) if described_class.const_defined?(:MaintenanceRecord,
                                                                                                false)
    end

    # A stand-in for ActiveRecord::Base that logs which class connects where
    # and what SQL runs.
    # A stand-in for SQLite3::Backup that reports canned step statuses;
    # statuses past the list repeat the last one.
    def fake_backup(statuses)
      instance_double(SQLite3::Backup).tap do |backup|
        allow(backup).to receive(:step).and_return(*statuses)
        allow(backup).to receive(:finish)
      end
    end

    def fake_connection(calls, template_sessions)
      connection = Object.new
      connection.define_singleton_method(:quote_table_name) { |name| %("#{name}") }
      connection.define_singleton_method(:quote) { |value| "'#{value}'" }
      connection.define_singleton_method(:execute) { |sql| calls << sql }
      connection.define_singleton_method(:select_values) { |*| template_sessions }
      connection
    end

    def fake_base(db, template_sessions: [])
      calls = log
      connection = fake_connection(calls, template_sessions)
      pool = Object.new
      pool.define_singleton_method(:with_connection) { |&block| block.call(connection) }
      Class.new.tap do |base|
        base.singleton_class.attr_accessor(:abstract_class)
        base.define_singleton_method(:establish_connection) do |config|
          calls << [equal?(base) ? :app : :maintenance, config[:database]]
        end
        base.define_singleton_method(:connection_pool) { pool }
        base.define_singleton_method(:remove_connection) { calls << :removed }
        handler = Object.new
        handler.define_singleton_method(:connection_pool_list) { |_role| [] }
        base.define_singleton_method(:connection_handler) { handler }
        base.define_singleton_method(:configurations) do
          Object.new.tap { |c| c.define_singleton_method(:configs_for) { |**| [db] } }
        end
      end
    end

    # Rails 7.1+ resolves a relative sqlite path against Rails.root, not
    # the process working directory; create AND cleanup must use the same
    # resolution, or a run from another working directory leaks its copies
    # (and can delete a same-named file under the working directory).
    it "creates and drops the copy under Rails.root, whatever the working directory" do
      Dir.mktmpdir do |dir|
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new("db/test.sqlite3", { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        rails_root = Module.new
        rails_root.define_singleton_method(:root) { Pathname.new(dir) }
        stub_const("Rails", rails_root)
        FileUtils.mkdir_p(File.join(dir, "db"))
        source = File.join(dir, "db", "test.sqlite3")
        SQLite3::Database.new(source) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        target = File.join(dir, "db", "test_saboteur2.sqlite3")
        Dir.chdir("/") do
          rails.prepare_workers(2)
          expect(File).to exist(target)
          rails.cleanup_workers
          expect(File).not_to exist(target)
        end
      end
    end

    # A missing source must not become a silent skip: the worker would get
    # a fresh empty database and test nothing.
    it "raises when the sqlite source file does not exist" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(missing, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /#{Regexp.escape(missing)}/)
      end
    end

    # Real SQLite, in WAL mode. wal_checkpoint(TRUNCATE) reports a busy
    # reader instead of raising; copying on would silently miss the
    # committed rows still outside the main file, so the copy refuses.
    it "refuses to copy while a reader keeps the WAL busy" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        writer = SQLite3::Database.new(path)
        writer.execute("PRAGMA journal_mode=WAL")
        writer.execute("CREATE TABLE t (i)")
        writer.execute("INSERT INTO t VALUES (1)")
        reader = SQLite3::Database.new(path)
        reader.execute("BEGIN")
        reader.execute("SELECT * FROM t")
        writer.execute("INSERT INTO t VALUES (2)")
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not checkpoint/)
        reader.execute("ROLLBACK")
        reader.close
        writer.close
      end
    end

    # The backup API snapshots a consistent image, WAL contents included;
    # a byte copy of main + WAL + SHM can catch a write between the file
    # copies and come out malformed.
    it "snapshots rows still living in the WAL into the copy" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        writer = SQLite3::Database.new(path)
        writer.execute("PRAGMA journal_mode=WAL")
        writer.execute("CREATE TABLE t (i)")
        writer.execute("INSERT INTO t VALUES (1)")
        rails.prepare_workers(2)
        target = File.join(dir, "test_saboteur2.sqlite3")
        copy = SQLite3::Database.new(target)
        expect(copy.execute("SELECT COUNT(*) FROM t").first).to eq([1])
        copy.close
        writer.close
      end
    end

    # Stale -wal/-shm sidecars from an earlier byte copy would shadow the
    # fresh snapshot, so the target starts clean. SQLite discards invalid
    # sidecars itself on open, so pin the removal calls directly.
    it "removes the target and any stale sidecars before snapshotting" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        allow(FileUtils).to receive(:rm_f).and_call_original
        rails.prepare_workers(2)
        target = File.join(dir, "test_saboteur2.sqlite3")
        expect(FileUtils).to have_received(:rm_f).with(target)
        expect(FileUtils).to have_received(:rm_f).with("#{target}-wal")
        expect(FileUtils).to have_received(:rm_f).with("#{target}-shm")
      end
    end

    # Stale -wal/-shm sidecars from an earlier byte copy would shadow the
    # fresh snapshot, so the target starts clean.
    it "removes stale WAL and SHM sidecars the snapshot does not replace" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) do |sqlite|
          sqlite.execute("CREATE TABLE t (i)")
          sqlite.execute("INSERT INTO t VALUES (1)")
        end
        target = File.join(dir, "test_saboteur2.sqlite3")
        File.write("#{target}-wal", "stale")
        File.write("#{target}-shm", "stale")
        rails.prepare_workers(2)
        expect(File).not_to exist("#{target}-wal")
        expect(File).not_to exist("#{target}-shm")
        copy = SQLite3::Database.new(target)
        expect(copy.execute("SELECT COUNT(*) FROM t").first).to eq([1])
        copy.close
      end
    end

    # A checkpoint that reports frames left behind without a busy flag
    # still failed to finish; both halves of the fail-closed check matter.
    it "refuses to copy when the checkpoint leaves frames behind" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        connection = double("connection")
        allow(connection).to receive(:execute).with("PRAGMA wal_checkpoint(TRUNCATE)").and_return([[0, 4, 3]])
        allow(rails).to receive(:with_sqlite).and_yield(connection)
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not checkpoint/)
      end
    end

    it "refuses to copy when the checkpoint is busy even with no frames left" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        connection = double("connection")
        allow(connection).to receive(:execute).with("PRAGMA wal_checkpoint(TRUNCATE)").and_return([[1, 0, 0]])
        allow(rails).to receive(:with_sqlite).and_yield(connection)
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not checkpoint/)
      end
    end

    # Without finish the backup handle is never released; pin that the
    # copy ends through it.
    it "finishes the backup after stepping every page" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        finished = false
        allow(SQLite3::Backup).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |backup|
            allow(backup).to receive(:finish).and_wrap_original do |finish|
              finished = true
              finish.call
            end
          end
        end
        rails.prepare_workers(2)
        expect(finished).to be(true)
      end
    end

    # A real exclusive lock from another connection makes SQLite report
    # the lock instead of raising through ActiveRecord; the copy must fail
    # closed, here at the checkpoint.
    it "refuses to copy while another connection holds the source exclusively" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        locker = SQLite3::Database.new(path)
        locker.execute("BEGIN EXCLUSIVE")
        locker.execute("INSERT INTO t VALUES (1)")
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not checkpoint/)
        locker.execute("ROLLBACK")
        locker.close
      end
    end

    # Backup#step returns raw SQLite status codes instead of raising, so a
    # busy target must be retried and a hard status must fail the copy.
    it "retries a busy backup step and copies once it completes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        statuses = [5, 5]
        fake = fake_backup(statuses + [101])
        allow(SQLite3::Backup).to receive(:new).and_return(fake)
        rails.prepare_workers(2)
        expect(fake).to have_received(:step).exactly(3).times
      end
    end

    it "fails the copy when the backup step reports an error status" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        fake = fake_backup([10])
        allow(SQLite3::Backup).to receive(:new).and_return(fake)
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not copy.*status 10/)
        expect(fake).to have_received(:finish)
      end
    end

    it "fails the copy when the backup step stays busy" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        fake = fake_backup([5])
        allow(SQLite3::Backup).to receive(:new).and_return(fake)
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not copy.*still busy/)
        expect(fake).to have_received(:finish)
      end
    end

    # Real lock, real backup: a source locked exclusively makes step report
    # BUSY or LOCKED through the binding until the retries run out. The
    # checkpoint gate is stubbed here; its own locked case is covered above.
    it "fails the copy when the source stays locked through the backup" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        locker = SQLite3::Database.new(path)
        locker.execute("BEGIN EXCLUSIVE")
        locker.execute("INSERT INTO t VALUES (1)")
        allow(rails).to receive(:checkpoint_sqlite)
        expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /could not copy/)
        locker.execute("ROLLBACK")
        locker.close
      end
    end

    # A writable source handle would copy identically but could write to
    # the database under test; the snapshot must open it read-only.
    it "opens the source read-only for the snapshot" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.sqlite3")
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(path, { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        SQLite3::Database.new(path) { |sqlite| sqlite.execute("CREATE TABLE t (i)") }
        allow(SQLite3::Database).to receive(:new).and_call_original
        rails.prepare_workers(2)
        expect(SQLite3::Database).to have_received(:new).with(path, readonly: true)
      end
    end

    it "resolves only relative sqlite paths, and only with Rails present" do
      expect(rails.send(:sqlite_absolute, "/data/test.sqlite3")).to eq("/data/test.sqlite3")
      expect(rails.send(:sqlite_absolute, "db/test.sqlite3")).to eq("db/test.sqlite3")
    end

    # Copying runs CREATE DATABASE from the maintenance database. Doing that
    # through the app's own connection left every worker on "postgres", with
    # no tables (human-essentials, --jobs 3).
    it "copies the test database without touching the app's connection" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(2)
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"',
                         'CREATE DATABASE "app_test_saboteur2" TEMPLATE "app_test"', :removed])
    end

    # Postgres refuses CREATE DATABASE ... TEMPLATE while any other session
    # is connected to the template (field report, issue 7); name the
    # blockers instead of dying mid-run with the raw error.
    it "names the sessions blocking the template copy instead of failing mid-run" do
      stub_const("ActiveRecord::Base",
                 fake_base(fake_pool(:writing).db_config, template_sessions: ["psql", ""]))
      expect { rails.prepare_workers(2) }.to raise_error(
        Saboteur::Error,
        "cannot copy the test database app_test: 2 other session(s) connected (psql, unnamed). " \
        "Stop other test runs, consoles or Spring, then run saboteur again."
      )
      expect(log).not_to include('CREATE DATABASE "app_test_saboteur2" TEMPLATE "app_test"')
    end

    # pg_stat_activity.application_name can be NULL (older servers, some
    # drivers) as well as empty.
    it "treats a NULL application name as unnamed" do
      stub_const("ActiveRecord::Base",
                 fake_base(fake_pool(:writing).db_config, template_sessions: [nil]))
      expect { rails.prepare_workers(2) }.to raise_error(Saboteur::Error, /1 other session.*unnamed/)
    end

    it "bounds the number of session names in the error" do
      stub_const("ActiveRecord::Base",
                 fake_base(fake_pool(:writing).db_config, template_sessions: %w[a b c d e f g]))
      expect { rails.prepare_workers(2) }.to raise_error(
        Saboteur::Error, /7 other session.*connected \(a, b, c, d, e\), \.\.\./
      )
    end
    # The database lives in the parent's connection, so there is no file to
    # copy: workers inherit it through fork. The doorkeeper dogfood broke
    # here - every example failed "Could not find table" after the copies
    # renamed the memory database.
    it "makes no copies for an in-memory sqlite database and tracks nothing to clean up" do
      db = Struct.new(:database, :configuration_hash, :adapter)
                 .new(":memory:", { adapter: "sqlite3", database: ":memory:" }, "sqlite3")
      base = fake_base(db)
      stub_const("ActiveRecord::Base", base)
      allow(SQLite3::Database).to receive(:new).and_call_original
      rails.prepare_workers(2)
      expect(SQLite3::Database).not_to have_received(:new)
      expect { rails.cleanup_workers }.not_to raise_error
    end
  end

  describe "in-memory sqlite snapshots" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

    # A pool stand-in over a real SQLite handle; db_config is shared with
    # the "child" pool, the way a forked process shares the parent's pool
    # definitions.
    def memory_pool(sqlite, db)
      connection = Struct.new(:raw_connection).new(sqlite)
      Object.new.tap do |pool|
        pool.define_singleton_method(:db_config) { db }
        pool.define_singleton_method(:with_connection) { |&block| block.call(connection) }
        pool.define_singleton_method(:disconnect!) { nil }
      end
    end

    def memory_db
      Struct.new(:database, :configuration_hash, :adapter)
            .new(":memory:", { adapter: "sqlite3", database: ":memory:" }, "sqlite3")
    end

    def base_with(pools)
      handler = Object.new
      handler.define_singleton_method(:connection_pool_list) { |*| pools }
      double("ActiveRecord::Base", connection_handler: handler)
    end

    # The parent snapshots after boot; the child sees a fresh, empty
    # in-memory database for the same config (ActiveRecord discards the
    # inherited pool) and restores the snapshot into it.
    it "snapshots the parent's database and restores it into the child's fresh one" do
      parent_sqlite = SQLite3::Database.new(":memory:")
      parent_sqlite.execute("CREATE TABLE t (i)")
      parent_sqlite.execute("INSERT INTO t VALUES (1)")
      db = memory_db
      stub_const("ActiveRecord::Base", base_with([memory_pool(parent_sqlite, db)]))
      rails.send(:snapshot_memory_databases)
      dir = rails.instance_variable_get(:@memory_snapshot_dir)
      expect(File.basename(dir)).to start_with("saboteur-memory-")
      child_sqlite = SQLite3::Database.new(":memory:")
      stub_const("ActiveRecord::Base", base_with([memory_pool(child_sqlite, db)]))
      allow(SQLite3::Database).to receive(:new).and_call_original
      rails.send(:restore_memory_databases)
      expect(child_sqlite.execute("SELECT COUNT(*) FROM t").first.first).to eq(1)
      # The snapshot belongs to the parent; restore opens it read-only.
      expect(SQLite3::Database).to have_received(:new).with(a_string_starting_with(dir), readonly: true)
    end

    it "restores again without duplicating rows" do
      parent_sqlite = SQLite3::Database.new(":memory:")
      parent_sqlite.execute("CREATE TABLE t (i)")
      parent_sqlite.execute("INSERT INTO t VALUES (1)")
      db = memory_db
      stub_const("ActiveRecord::Base", base_with([memory_pool(parent_sqlite, db)]))
      rails.send(:snapshot_memory_databases)
      child_sqlite = SQLite3::Database.new(":memory:")
      stub_const("ActiveRecord::Base", base_with([memory_pool(child_sqlite, db)]))
      2.times { rails.send(:restore_memory_databases) }
      expect(child_sqlite.execute("SELECT COUNT(*) FROM t").first.first).to eq(1)
    end

    it "does nothing when no pool is in-memory" do
      stub_const("ActiveRecord::Base", base_with([]))
      rails.send(:snapshot_memory_databases)
      expect(rails.instance_variable_get(:@memory_snapshot_dir)).to be_nil
      expect { rails.send(:restore_memory_databases) }.not_to raise_error
    end

    it "removes the snapshot directory at cleanup" do
      parent_sqlite = SQLite3::Database.new(":memory:")
      parent_sqlite.execute("CREATE TABLE t (i)")
      stub_const("ActiveRecord::Base", base_with([memory_pool(parent_sqlite, memory_db)]))
      rails.send(:snapshot_memory_databases)
      dir = rails.instance_variable_get(:@memory_snapshot_dir)
      rails.cleanup_workers
      expect(Dir.exist?(dir)).to be(false)
      expect(rails.instance_variable_get(:@memory_snapshot_dir)).to be_nil
      expect(rails.instance_variable_get(:@memory_snapshots)).to eq({})
    end

    # A pool with no snapshot (added after boot, or not in-memory at
    # snapshot time) is left alone.
    it "skips pools without a snapshot" do
      parent_sqlite = SQLite3::Database.new(":memory:")
      parent_sqlite.execute("CREATE TABLE t (i)")
      stub_const("ActiveRecord::Base", base_with([memory_pool(parent_sqlite, memory_db)]))
      rails.send(:snapshot_memory_databases)
      other_sqlite = SQLite3::Database.new(":memory:")
      stub_const("ActiveRecord::Base", base_with([memory_pool(other_sqlite, memory_db)]))
      expect { rails.send(:restore_memory_databases) }.not_to raise_error
      expect(other_sqlite.execute("SELECT name FROM sqlite_master")).to be_empty
    end

    # Without ActiveRecord the restore must not touch the snapshots: the
    # child only reaches it when the app booted.
    it "restores nothing when ActiveRecord is not loaded" do
      rails.instance_variable_set(:@memory_snapshots, { memory_db => "x" })
      hide_const("ActiveRecord")
      expect { rails.send(:restore_memory_databases) }.not_to raise_error
    end

    it "restores on reconnect and when a worker starts" do
      stub_const("ActiveRecord::Base", base_with([]))
      allow(rails).to receive(:restore_memory_databases)
      rails.send(:reconnect)
      rails.start_worker(1)
      expect(rails).to have_received(:restore_memory_databases).twice
    end
  end

  describe "#disconnect" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

    # A real in-memory database: disconnecting its pool would close the
    # connection and drop every table, which is how the doorkeeper dogfood
    # lost its schema. File-backed pools still disconnect.
    it "keeps a real in-memory sqlite database alive and still disconnects file pools" do
      sqlite = SQLite3::Database.new(":memory:")
      sqlite.execute("CREATE TABLE t (i)")
      sqlite.execute("INSERT INTO t VALUES (1)")
      memory_db = Struct.new(:database, :configuration_hash, :adapter)
                        .new(":memory:", { adapter: "sqlite3", database: ":memory:" }, "sqlite3")
      memory_pool = Object.new
      memory_pool.define_singleton_method(:db_config) { memory_db }
      memory_pool.define_singleton_method(:disconnect!) { sqlite.close }
      file_db = Struct.new(:database, :configuration_hash, :adapter)
                      .new("app_test", { adapter: "sqlite3", database: "app_test" }, "sqlite3")
      file_pool = Object.new
      file_pool.define_singleton_method(:db_config) { file_db }
      file_disconnected = false
      file_pool.define_singleton_method(:disconnect!) { file_disconnected = true }
      handler = double("handler", connection_pool_list: [memory_pool, file_pool])
      stub_const("ActiveRecord::Base", double("ActiveRecord::Base", connection_handler: handler))
      rails.send(:disconnect)
      expect(file_disconnected).to be(true)
      expect(sqlite.execute("SELECT COUNT(*) FROM t").first.first).to eq(1)
    end
  end

  describe "#cleanup_workers" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
    let(:log) { [] }

    after do
      described_class.send(:remove_const, :MaintenanceRecord) if described_class.const_defined?(:MaintenanceRecord,
                                                                                                false)
    end

    # Same stand-in as #prepare_workers: logs which class connects where and
    # what SQL runs.
    def fake_connection(calls)
      Object.new.tap do |connection|
        connection.define_singleton_method(:quote_table_name) { |name| %("#{name}") }
        connection.define_singleton_method(:quote) { |value| "'#{value}'" }
        connection.define_singleton_method(:execute) { |sql| calls << sql }
        connection.define_singleton_method(:select_values) { |_sql| [] }
      end
    end

    def fake_base(db)
      calls = log
      connection = fake_connection(calls)
      pool = Object.new
      pool.define_singleton_method(:with_connection) { |&block| block.call(connection) }
      Class.new.tap do |base|
        base.singleton_class.attr_accessor(:abstract_class)
        base.define_singleton_method(:establish_connection) do |config|
          calls << [equal?(base) ? :app : :maintenance, config[:database]]
        end
        base.define_singleton_method(:connection_pool) { pool }
        base.define_singleton_method(:remove_connection) { calls << :removed }
        handler = Object.new
        handler.define_singleton_method(:connection_pool_list) { |_role| [] }
        base.define_singleton_method(:connection_handler) { handler }
        base.define_singleton_method(:configurations) do
          Object.new.tap { |c| c.define_singleton_method(:configs_for) { |**| [db] } }
        end
      end
    end

    it "drops every copy prepare_workers made, through the maintenance connection" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(3)
      log.clear
      rails.cleanup_workers
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"', :removed,
                         [:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur3"', :removed])
    end

    # The copy for saboteur3 was really made before the error, so it must
    # be dropped too - tracking after copy_database returns would leak it.
    it "drops the copies a failed prepare attempted, including the one that failed" do
      db = fake_pool(:writing).db_config
      base = fake_base(db)
      stub_const("ActiveRecord::Base", base)
      allow(rails).to receive(:copy_database).and_wrap_original do |original, config, name|
        original.call(config, name)
        raise "disk full" if name.end_with?("saboteur3")
      end
      expect { rails.prepare_workers(3) }.to raise_error("disk full")
      log.clear
      rails.cleanup_workers
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"', :removed,
                         [:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur3"', :removed])
    end

    # A disconnect that raises must not escape as an unrescued error and
    # mask the run's outcome; it is reported with the drop failures.
    it "reports a failed disconnect with the drop failures" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(2)
      log.clear
      allow(rails).to receive(:disconnect).and_raise("handler exploded")
      expect { rails.cleanup_workers }.to raise_error(
        Saboteur::Error,
        /could not drop worker database copies: app_test_saboteur2: handler exploded; disconnect: handler exploded/
      )
      # The drop was attempted even though its disconnect failed.
      expect(rails.instance_variable_get(:@worker_copies)).to be_empty
    end

    it "keeps dropping after a failed drop and reports every failure at the end" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(3)
      log.clear
      allow(rails).to receive(:drop_database) do |db, name|
        raise "server closed the connection" if name.end_with?("saboteur2")

        ["", "-wal", "-shm"].each { |suffix| FileUtils.rm_f("#{name}#{suffix}") } if db.adapter =~ /sqlite/
        log << "dropped #{name}"
      end
      expect { rails.cleanup_workers }.to raise_error(
        Saboteur::Error, /could not drop worker database copies: app_test_saboteur2: server closed the connection/
      )
      expect(log).to include("dropped app_test_saboteur3")
      expect { rails.cleanup_workers }.not_to raise_error
    end

    it "removes SQLite copies, including WAL and SHM files" do
      Dir.mktmpdir do |dir|
        db = Struct.new(:database, :configuration_hash, :adapter)
                   .new(File.join(dir, "test.sqlite3"), { adapter: "sqlite3" }, "sqlite3")
        stub_const("ActiveRecord::Base", fake_base(db))
        writer = SQLite3::Database.new(db.database)
        writer.execute("PRAGMA journal_mode=WAL")
        writer.execute("CREATE TABLE t (i)")
        rails.prepare_workers(2)
        expect(Dir.children(dir)).to include("test_saboteur2.sqlite3")
        # Give the copy real sidecars of its own, so the drop has to
        # remove them rather than pass on their absence.
        copy = SQLite3::Database.new(File.join(dir, "test_saboteur2.sqlite3"))
        copy.execute("PRAGMA journal_mode=WAL")
        copy.execute("INSERT INTO t VALUES (1)")
        expect(Dir.children(dir)).to include("test_saboteur2.sqlite3-wal")
        rails.cleanup_workers
        expect(Dir.children(dir)).not_to include("test_saboteur2.sqlite3", "test_saboteur2.sqlite3-wal",
                                                 "test_saboteur2.sqlite3-shm")
        expect(Dir.children(dir)).to include("test.sqlite3")
        copy.close
        writer.close
      end
    end

    it "does nothing when prepare_workers made no copies" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(1)
      rails.cleanup_workers
      expect(log).to be_empty
    end

    # With nothing to drop there is nothing to disconnect from: reaching
    # disconnect would mask the early return as a no-op.
    it "does not even disconnect when there are no copies to drop" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(1)
      expect(rails).not_to receive(:disconnect)
      rails.cleanup_workers
    end

    # A second prepare replaces the tracked set: without the reset, the
    # first attempt's names would be dropped twice.
    it "tracks only the latest prepare's copies when prepare runs twice" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(2)
      rails.prepare_workers(3)
      log.clear
      rails.cleanup_workers
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"', :removed,
                         [:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur3"', :removed])
    end
  end

  describe "#before_boot" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

    # libpq's GSSAPI probe crashes forked processes on macOS (Kerberos goes
    # through XPC, which is not fork-safe): every mutant at --jobs 3 on
    # human-essentials died with SIGSEGV. Databases are local only, so GSS
    # encryption buys nothing.
    it "turns off libpq GSS encryption unless the user chose a mode" do
      stub_const("ENV", { "RAILS_ENV" => "test" })
      rails.before_boot
      expect(ENV.fetch("PGGSSENCMODE")).to eq("disable")
    end

    it "keeps a GSS encryption mode the user set" do
      stub_const("ENV", { "RAILS_ENV" => "test", "PGGSSENCMODE" => "prefer" })
      rails.before_boot
      expect(ENV.fetch("PGGSSENCMODE")).to eq("prefer")
    end

    # Bytecode from Bootsnap's compile cache has no coverage counters, so a
    # file served from the cache is invisible to the coverage map. Turning
    # the cache off must happen here, before config/boot loads Bootsnap.
    it "turns off Bootsnap's compile cache unless the user chose" do
      stub_const("ENV", { "RAILS_ENV" => "test" })
      rails.before_boot
      expect(ENV.fetch("DISABLE_BOOTSNAP_COMPILE_CACHE")).to eq("1")
    end

    it "keeps a compile-cache choice the user set" do
      stub_const("ENV", { "RAILS_ENV" => "test", "DISABLE_BOOTSNAP_COMPILE_CACHE" => "0" })
      rails.before_boot
      expect(ENV.fetch("DISABLE_BOOTSNAP_COMPILE_CACHE")).to eq("0")
    end
  end

  describe "#after_boot" do
    let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
    let(:application) { double("application", eager_load!: nil) }

    before do
      stub_const("Rails", double("Rails", env: double("env", test?: true), application: application))
      allow(Coverage).to receive(:state).and_return(:suspended)
      allow(Coverage).to receive(:resume)
      allow(Coverage).to receive(:suspend)
    end

    it "snapshots in-memory sqlite databases for the forked children" do
      base = double("ActiveRecord::Base")
      handler = double("handler", connection_pool_list: [])
      allow(base).to receive(:connection_handler).and_return(handler)
      allow(base).to receive(:configurations).and_return(double("configs", configs_for: []))
      stub_const("ActiveRecord::Base", base)
      allow(rails).to receive(:snapshot_memory_databases)
      rails.after_boot
      expect(rails).to have_received(:snapshot_memory_databases)
    end

    it "points engine users at the dummy environment, and at the setup shim only without one" do
      hide_const("Rails")
      expect { rails.after_boot }.to raise_error(
        Saboteur::Error,
        %r{add config/environment to require.*test/dummy/config/environment\.rb.*dynamically.*DummyApp\.setup}m
      )
    end

    # Bootsnap serves cached bytecode unless Coverage is running, and cached
    # bytecode has no coverage counters (field report, issue 1). The eager
    # load is where most app files come in, so Coverage runs across it.
    it "resumes Coverage just around the eager load" do
      expect(Coverage).to receive(:resume).ordered
      expect(application).to receive(:eager_load!).ordered
      expect(Coverage).to receive(:suspend).ordered
      rails.after_boot
    end

    it "does not suspend when Coverage.resume itself fails" do
      allow(Coverage).to receive(:resume).and_raise("cannot resume")
      expect(Coverage).not_to receive(:suspend)
      expect(application).not_to receive(:eager_load!)
      expect { rails.after_boot }.to raise_error("cannot resume")
    end

    it "suspends Coverage again when the eager load raises" do
      allow(application).to receive(:eager_load!).and_raise("boom")
      expect(Coverage).to receive(:resume).ordered
      expect(Coverage).to receive(:suspend).ordered
      expect { rails.after_boot }.to raise_error("boom")
    end

    it "leaves Coverage alone when it is already running" do
      allow(Coverage).to receive(:state).and_return(:running)
      expect(Coverage).not_to receive(:resume)
      expect(Coverage).not_to receive(:suspend)
      rails.after_boot
    end
  end

  describe ".memory_database?" do
    def db(database, adapter)
      Struct.new(:database, :configuration_hash, :adapter).new(database, { adapter: adapter }, adapter)
    end

    it "matches only an in-memory sqlite database" do
      expect(described_class.memory_database?(db(":memory:", "sqlite3"))).to be(true)
      expect(described_class.memory_database?(db("app_test", "sqlite3"))).to be(false)
      expect(described_class.memory_database?(db(":memory:", "postgresql"))).to be(false)
    end
  end

  describe ".local_host?" do
    it "accepts local hosts and sockets only" do
      expect(%w[localhost 127.0.0.1 ::1 /tmp/pg].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect([nil, ""].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect(described_class.local_host?("db.example.com")).to be(false)
    end
  end
end
