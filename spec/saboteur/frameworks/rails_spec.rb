# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
