# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "rbconfig"

# The detector reads process-global ActiveRecord state, so each scenario
# runs in its own subprocess: no connection leaks into the suite's own
# process (#387).
RSpec.describe Saboteur::Frameworks::SqliteMemoryDatabase do
  def hint_in(script)
    program = <<~RUBY
      $LOAD_PATH.unshift #{File.expand_path('../../../lib', __dir__).inspect}
      require "saboteur/frameworks/sqlite_memory_database"
      #{script}
      hint = Saboteur::Frameworks::SqliteMemoryDatabase.fork_loss_hint
      puts(hint ? "HINT" : "NONE")
    RUBY
    out, = Open3.capture2(RbConfig.ruby, "-e", program)
    out.lines.last.to_s.strip
  end

  it "shows the hooks file and the exact wiring needed in config/saboteur.rb (#593)" do
    pool = double("empty sqlite pool")
    handler = double("connection handler", connection_pool_list: [pool])
    stub_const("ActiveRecord::Base", double("ActiveRecord base", connection_handler: handler))
    allow(described_class).to receive(:empty_memory_database?).with(pool).and_return(true)
    expect(described_class.fork_loss_hint).to eq(
      "a sqlite :memory: database is empty in this forked child: in-memory databases do not " \
      "survive saboteur's fork, so a schema loaded at require time is lost. Load the schema in " \
      "a before(:suite) hook, or in an after_fork hook in config/saboteur_hooks.rb; wire it in " \
      'config/saboteur.rb with c.hooks = ["config/saboteur_hooks.rb"]'
    )
  end

  it "only suggests the remedy when at least one current pool lost its schema" do
    handler = double("connection handler", connection_pool_list: %i[healthy empty])
    stub_const("ActiveRecord::Base", double("ActiveRecord base", connection_handler: handler))
    allow(described_class).to receive(:empty_memory_database?).with(:healthy).and_return(false)
    allow(described_class).to receive(:empty_memory_database?).with(:empty).and_return(true)
    expect(described_class.fork_loss_hint).to eq(described_class::REMEDY)
    allow(handler).to receive(:connection_pool_list).and_return([:healthy])
    expect(described_class.fork_loss_hint).to be_nil
  end

  it "names the remedy when a sqlite :memory: database has no schema" do
    expect(hint_in(<<~RUBY)).to eq("HINT")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    RUBY
  end

  it "names require-time seed data when the schema survived but every user table is empty (#594)" do
    expect(hint_in(<<~RUBY)).to eq("HINT")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define { create_table(:roles) { |t| t.string :name } }
    RUBY
  end

  it "pins the seed remedy: rows seeded at require time are lost across the fork (#594)" do
    pool = double("unseeded sqlite pool")
    handler = double("connection handler", connection_pool_list: [pool])
    stub_const("ActiveRecord::Base", double("ActiveRecord base", connection_handler: handler))
    allow(described_class).to receive(:empty_memory_database?).with(pool).and_return(false)
    allow(described_class).to receive(:unseeded_memory_database?).with(pool).and_return(true)
    expect(described_class.fork_loss_hint).to eq(
      "a sqlite :memory: database in this forked child has its schema but no rows: rows seeded at " \
      "require time (seed data, fixtures loaded at boot) are lost across saboteur's fork, just like " \
      "the schema. Seed in a before(:suite) hook, or in an after_fork hook in config/saboteur_hooks.rb; " \
      'wire it in config/saboteur.rb with c.hooks = ["config/saboteur_hooks.rb"]'
    )
  end

  it "detects the seed-loss shape in process: schema present, every user table empty (#594)" do
    connection = double("sqlite connection")
    allow(connection).to receive(:select_values)
      .with("SELECT name FROM sqlite_master WHERE type = 'table'")
      .and_return(%w[roles schema_migrations])
    allow(connection).to receive(:quote_table_name).with("roles").and_return('"roles"')
    allow(connection).to receive(:select_value).with('SELECT 1 FROM "roles" LIMIT 1').and_return(nil)
    pool = double("sqlite pool", db_config: double("db config", adapter: "sqlite3", database: ":memory:"))
    allow(pool).to receive(:with_connection).and_yield(connection)

    expect(described_class.unseeded_memory_database?(pool)).to be(true)
  end

  it "is not the seed-loss shape when a user table holds rows or the database is a file (#594)" do
    connection = double("sqlite connection")
    allow(connection).to receive(:select_values)
      .with("SELECT name FROM sqlite_master WHERE type = 'table'")
      .and_return(%w[roles schema_migrations])
    allow(connection).to receive(:quote_table_name).with("roles").and_return('"roles"')
    allow(connection).to receive(:select_value).with('SELECT 1 FROM "roles" LIMIT 1').and_return(1)
    seeded = double("seeded pool", db_config: double("db config", adapter: "sqlite3", database: ":memory:"))
    allow(seeded).to receive(:with_connection).and_yield(connection)
    file_pool = double("file pool", db_config: double("db config", adapter: "sqlite3", database: "db/test.sqlite3"))

    expect(described_class.unseeded_memory_database?(seeded)).to be(false)
    expect(described_class.unseeded_memory_database?(file_pool)).to be(false)
  end

  it "suggests the seed remedy when at least one current pool lost its rows (#594)" do
    handler = double("connection handler", connection_pool_list: %i[healthy unseeded])
    stub_const("ActiveRecord::Base", double("ActiveRecord base", connection_handler: handler))
    allow(described_class).to receive(:empty_memory_database?).and_return(false)
    allow(described_class).to receive(:unseeded_memory_database?).with(:healthy).and_return(false)
    allow(described_class).to receive(:unseeded_memory_database?).with(:unseeded).and_return(true)
    expect(described_class.fork_loss_hint).to eq(described_class::SEED_REMEDY)
    allow(handler).to receive(:connection_pool_list).and_return([:healthy])
    expect(described_class.fork_loss_hint).to be_nil
  end

  it "stays quiet once the memory database holds a user table with rows" do
    expect(hint_in(<<~RUBY)).to eq("NONE")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define { create_table(:widgets) { |t| t.integer :number } }
      ActiveRecord::Base.connection.execute("INSERT INTO widgets (number) VALUES (1)")
    RUBY
  end

  it "stays quiet for a file database, which survives a fork" do
    expect(hint_in(<<~RUBY)).to eq("NONE")
      require "active_record"
      require "tmpdir"
      path = File.join(Dir.mktmpdir, "test.sqlite3")
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path)
    RUBY
  end

  it "stays quiet when ActiveRecord is not loaded" do
    expect(hint_in("")).to eq("NONE")
  end

  it "treats a database with only migration bookkeeping as empty" do
    expect(hint_in(<<~RUBY)).to eq("HINT")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define { create_table(:schema_migrations) { |t| t.string :version } }
    RUBY
  end
end
