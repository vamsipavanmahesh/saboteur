# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "sqlite3"

# Database copying for --jobs workers: the adapter dispatch, the missing
# source, relative paths, the checkpoint check and the backup retries, each
# with its exact message.
RSpec.describe Saboteur::Frameworks::Rails, "database copy messages" do
  let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

  describe "#test_configs" do
    it "asks ActiveRecord for the test environment's configurations" do
      configurations = double("configurations")
      allow(configurations).to receive(:configs_for).with(env_name: "test").and_return([:cfg])
      stub_const("ActiveRecord::Base", double("ActiveRecord::Base", configurations:))
      expect(rails.send(:test_configs)).to eq([:cfg])
    end
  end

  describe "#copy_database" do
    it "disconnects before a Postgres copy, copies SQLite by file, and refuses other adapters" do
      allow(rails).to receive(:disconnect)
      allow(rails).to receive(:copy_postgres)
      allow(rails).to receive(:copy_sqlite)
      pg = double("pg", adapter: "postgresql")
      rails.send(:copy_database, pg, "w2")
      expect(rails).to have_received(:disconnect).ordered
      expect(rails).to have_received(:copy_postgres).with(pg, "w2").ordered
      lite = double("lite", adapter: "sqlite3")
      rails.send(:copy_database, lite, "w3")
      expect(rails).to have_received(:copy_sqlite).with(lite, "w3")
      expect { rails.send(:copy_database, double("my", adapter: "mysql2"), "w4") }.to raise_error(
        Saboteur::Error, "--jobs > 1 with Rails needs Postgres or SQLite (got mysql2)"
      )
    end
  end

  describe "#copy_sqlite" do
    it "names a missing source and says how to create it" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "missing.sqlite3")
        expect { rails.send(:copy_sqlite, double("db", database: source), "w2") }.to raise_error(
          Saboteur::Error, "test database #{source} does not exist; run the test suite once to create it"
        )
      end
    end
  end

  describe "#sqlite_absolute" do
    it "keeps an absolute path, and resolves a relative one against Rails.root" do
      stub_const("Rails", double("Rails", root: Pathname.new("/app")))
      expect(rails.send(:sqlite_absolute, "/data/test.sqlite3")).to eq("/data/test.sqlite3")
      expect(rails.send(:sqlite_absolute, "db/test.sqlite3")).to eq("/app/db/test.sqlite3")
    end

    it "keeps a relative path as given when Rails is not loaded" do
      hide_const("Rails")
      expect(rails.send(:sqlite_absolute, "db/test.sqlite3")).to eq("db/test.sqlite3")
    end
  end

  describe "#checkpoint_sqlite" do
    def checkpoint_with(row)
      database = double("database", execute: [row, [9, 9, 9]])
      allow(rails).to receive(:with_sqlite).and_yield(database)
      rails.send(:checkpoint_sqlite, "/data/t.sqlite3")
    end

    it "accepts a complete pass and refuses a busy or incomplete one, with the numbers" do
      expect { checkpoint_with([0, 5, 5]) }.not_to raise_error
      expect { checkpoint_with([1, 5, 5]) }.to raise_error(
        Saboteur::Error,
        "could not checkpoint /data/t.sqlite3 before copying it (busy: 1, frames: 5, checkpointed: 5); " \
        "close the connections holding it and run again"
      )
      expect { checkpoint_with([0, 5, 4]) }.to raise_error(Saboteur::Error, /busy: 0, frames: 5, checkpointed: 4/)
    end

    it "turns a busy exception into the same advice" do
      allow(rails).to receive(:with_sqlite).and_raise(SQLite3::BusyException, "database is locked")
      expect { rails.send(:checkpoint_sqlite, "/data/t.sqlite3") }.to raise_error(
        Saboteur::Error,
        "could not checkpoint /data/t.sqlite3 before copying it (database is locked); " \
        "close the connections holding it and run again"
      )
    end
  end

  describe "#step_backup" do
    def backup_with(*statuses)
      instance_double(SQLite3::Backup).tap { |backup| allow(backup).to receive(:step).and_return(*statuses) }
    end

    before { allow(rails).to receive(:sleep) }

    it "retries a busy or locked step and stops at done" do
      backup = backup_with(described_class::SQLITE_BUSY, described_class::SQLITE_LOCKED, described_class::SQLITE_DONE)
      rails.send(:step_backup, backup, "t")
      expect(backup).to have_received(:step).with(-1).exactly(3).times
      expect(rails).to have_received(:sleep).with(described_class::BACKUP_RETRY_DELAY).twice
    end

    it "fails any other status with the status and the target" do
      expect { rails.send(:step_backup, backup_with(11), "/data/w2.sqlite3") }.to raise_error(
        Saboteur::Error, "could not copy the database to /data/w2.sqlite3: sqlite backup failed with status 11"
      )
    end

    it "gives up after the bounded number of busy attempts" do
      expect { rails.send(:step_backup, backup_with(described_class::SQLITE_BUSY), "/data/w2.sqlite3") }.to raise_error(
        Saboteur::Error, "could not copy the database to /data/w2.sqlite3: still busy after 5 attempts"
      )
    end
  end
end
