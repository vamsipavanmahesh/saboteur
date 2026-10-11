# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "spec_helper"
require "open3"

# A real ActiveRecord app whose test database is sqlite :memory:, forked
# the way the supervisor forks children. ActiveRecord discards the
# inherited pool after fork and sqlite3 closes inherited writable handles,
# so without a snapshot the child opens a NEW, EMPTY in-memory database and
# every query fails with "Could not find table". The dogfood against
# doorkeeper (188 examples) failed exactly so.
RSpec.describe "rails integration with an in-memory sqlite database" do
  def memory_fork_script(dir)
    path = File.join(dir, "memory_fork.rb")
    File.write(path, memory_fork_source)
    path
  end

  def memory_fork_source
    <<~RUBY
      ENV["RAILS_ENV"] = "test"
      require "active_record"
      require "saboteur"
      require "saboteur/frameworks/rails"

      module Rails
        def self.env = ActiveSupport::StringInquirer.new("test")
        def self.application = Object.new.tap { |app| def app.eager_load! = nil }
      end

      # The app boots: schema loads into the in-memory database.
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define { create_table(:things) { |t| t.integer :i } }
      ActiveRecord::Base.connection.execute("INSERT INTO things (i) VALUES (1)")

      hooks = Saboteur::Hooks.new
      rails = Saboteur::Frameworks::Rails.new(Saboteur::Config.new({}), hooks)
      rails.after_boot
      rails.prepare_workers(2)

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        hooks.run(:after_fork)
        rails.start_worker(1)
        count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM things").to_i
        writer.write(count.to_s)
        writer.close
        exit!(0)
      end
      writer.close
      Process.wait(pid)
      puts "child_count=\#{reader.read}"
      puts "parent_count=\#{ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM things').to_i}"
      rails.cleanup_workers
    RUBY
  end

  it "keeps the parent's database usable and lets a forked worker query it" do
    Dir.mktmpdir do |dir|
      lib = File.expand_path("../../lib", __dir__)
      env = { "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", lib, memory_fork_script(dir))
      # sqlite3 warns about the inherited writable handle it closes; that is
      # the fork-safety hook doing its job, not a failure.
      expect([status.exitstatus, out]).to eq([0, "child_count=1\nparent_count=1\n"])
      expect(err).not_to include("Could not find table")
    end
  end

  def early_exit_script(dir)
    path = File.join(dir, "early_exit.rb")
    File.write(path, <<~RUBY)
      ENV["RAILS_ENV"] = "test"
      require "active_record"
      require "saboteur"
      require "saboteur/frameworks/rails"

      module Rails
        def self.env = ActiveSupport::StringInquirer.new("test")
        def self.application = Object.new.tap { |app| def app.eager_load! = nil }
      end

      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      rails = Saboteur::Frameworks::Rails.new(Saboteur::Config.new({}), Saboteur::Hooks.new)
      rails.after_boot
      puts "snapshot_dir=\#{Dir.glob(File.join(Dir.tmpdir, 'saboteur-memory-*')).max_by { |p| File.mtime(p) }}"
      # A boot, baseline or coverage failure ends the run here, without
      # cleanup_workers ever running.
      exit(3)
    RUBY
    path
  end

  it "removes the snapshot directory when the run exits without cleanup" do
    Dir.mktmpdir do |dir|
      lib = File.expand_path("../../lib", __dir__)
      env = { "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
      out, = Open3.capture3(env, RbConfig.ruby, "-I", lib, early_exit_script(dir))
      snapshot_dir = out[/^snapshot_dir=(.+)$/, 1]
      expect(snapshot_dir).not_to be_nil
      expect(Dir.exist?(snapshot_dir)).to be(false)
    end
  end
  end
