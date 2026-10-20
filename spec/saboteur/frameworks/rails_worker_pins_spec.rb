# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# start_worker's guards and pool walk, the in-memory check, the exact
# non-local database refusal and what the eager load hands back.
RSpec.describe Saboteur::Frameworks::Rails, "worker setup details" do
  let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }

  def db_double(adapter, database)
    double("db", adapter:, database:)
  end

  describe "#start_worker" do
    it "does nothing, and does not fail, without ActiveRecord" do
      hide_const("ActiveRecord::Base")
      allow(rails).to receive(:restore_memory_databases)
      expect(rails.start_worker(1)).to be_nil
      expect(rails).not_to have_received(:restore_memory_databases)
    end

    it "asks for the pools of every role and shard, walks them as an array and restores memory databases once" do
      pools = double("pools")
      allow(pools).to receive(:to_a).and_return([])
      handler = double("handler")
      allow(handler).to receive(:connection_pool_list).with(:all).and_return(pools)
      stub_const("ActiveRecord::Base", double("ActiveRecord::Base", connection_handler: handler))
      allow(rails).to receive(:restore_memory_databases)
      rails.start_worker(2)
      expect(handler).to have_received(:connection_pool_list).with(:all)
      expect(pools).to have_received(:to_a)
      expect(rails).to have_received(:restore_memory_databases).once
    end
  end

  describe ".memory_database?" do
    it "is true only for a sqlite database named :memory:, whatever the types" do
      expect(described_class.memory_database?(db_double(:sqlite3, :":memory:"))).to be(true)
      expect(described_class.memory_database?(db_double(nil, ":memory:"))).to be(false)
      expect(described_class.memory_database?(db_double("sqlite3", nil))).to be(false)
      expect(described_class.memory_database?(db_double("sqlite3", ":memory:"))).to be(true)
    end
  end

  describe "#check_databases" do
    it "words the refusal in full" do
      primary = double("primary", name: "primary", configuration_hash: { host: "db.internal" })
      base = double("ActiveRecord::Base")
      allow(base).to receive(:configurations).and_return(double("configurations", configs_for: [primary]))
      stub_const("ActiveRecord::Base", base)
      expect { rails.send(:check_databases) }.to raise_error(
        Saboteur::Error,
        "rails integration refuses to run against non-local databases: primary (host db.internal); " \
        "if they are disposable test databases, allow them with c.allow_db_hosts in #{Saboteur::Config::FILE}"
      )
    end

    it "does nothing without ActiveRecord" do
      hide_const("ActiveRecord::Base")
      expect(rails.send(:check_databases)).to be_nil
    end
  end

  describe "#eager_load_with_coverage_running" do
    it "returns what the eager load returned when Coverage is not suspended" do
      application = double("application", eager_load!: :loaded)
      stub_const("Rails", double("Rails", application:))
      allow(Coverage).to receive(:state).and_return(:running)
      expect(rails.send(:eager_load_with_coverage_running)).to eq(:loaded)
    end
  end
end
