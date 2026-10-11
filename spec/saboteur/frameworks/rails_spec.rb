# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
  def fake_pool(role, database: "app_test")
    config = Struct.new(:connection_descriptor, :role, :shard)
                   .new(Struct.new(:name).new("ActiveRecord::Base"), role, :default)
    db = Struct.new(:database, :configuration_hash, :adapter)
               .new(database, { adapter: "postgresql", database: database }, "postgresql")
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
    def fake_base(db)
      calls = log
      connection = Object.new
      connection.define_singleton_method(:quote_table_name) { |name| %("#{name}") }
      connection.define_singleton_method(:execute) { |sql| calls << sql }
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

    # Copying runs CREATE DATABASE from the maintenance database. Doing that
    # through the app's own connection left every worker on "postgres", with
    # no tables (human-essentials, --jobs 3).
    it "copies the test database without touching the app's connection" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(2)
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"',
                         'CREATE DATABASE "app_test_saboteur2" TEMPLATE "app_test"', :removed])
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
    def fake_base(db)
      calls = log
      connection = Object.new
      connection.define_singleton_method(:quote_table_name) { |name| %("#{name}") }
      connection.define_singleton_method(:execute) { |sql| calls << sql }
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

    it "drops only the copies a failed prepare actually made" do
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
      expect(log).to eq([[:maintenance, "postgres"], 'DROP DATABASE IF EXISTS "app_test_saboteur2"', :removed])
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
        ["", "-wal", "-shm"].each { |suffix| File.write("#{db.database}#{suffix}", "x") }
        rails.prepare_workers(2)
        rails.cleanup_workers
        expect(Dir.children(dir).sort).to eq(["test.sqlite3", "test.sqlite3-shm", "test.sqlite3-wal"])
      end
    end

    it "does nothing when prepare_workers made no copies" do
      stub_const("ActiveRecord::Base", fake_base(fake_pool(:writing).db_config))
      rails.prepare_workers(1)
      rails.cleanup_workers
      expect(log).to be_empty
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
  end

  describe ".local_host?" do
    it "accepts local hosts and sockets only" do
      expect(%w[localhost 127.0.0.1 ::1 /tmp/pg].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect([nil, ""].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect(described_class.local_host?("db.example.com")).to be(false)
    end
  end
end
