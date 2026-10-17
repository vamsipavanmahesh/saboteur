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
      require "saboteur"
      #{script}
      hint = Saboteur::Frameworks::SqliteMemoryDatabase.fork_loss_hint
      puts(hint ? "HINT" : "NONE")
    RUBY
    out, = Open3.capture2(RbConfig.ruby, "-e", program)
    out.lines.last.to_s.strip
  end

  it "names the remedy when a sqlite :memory: database has no schema" do
    expect(hint_in(<<~RUBY)).to eq("HINT")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    RUBY
  end

  it "stays quiet once the memory database holds a user table" do
    expect(hint_in(<<~RUBY)).to eq("NONE")
      require "active_record"
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define { create_table(:widgets) { |t| t.integer :number } }
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
