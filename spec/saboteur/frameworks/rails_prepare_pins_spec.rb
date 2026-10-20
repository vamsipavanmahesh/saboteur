# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# prepare_workers: when it copies, how many copies each database gets and
# which names they carry, what it skips, and that it disconnects once after.
RSpec.describe Saboteur::Frameworks::Rails, "#prepare_workers guards" do
  let(:rails) { described_class.new(Saboteur::Config.new({}), Saboteur::Hooks.new) }
  let(:db) { double("db", database: "app_test") }
  let(:copies) { [] }

  before do
    stub_const("ActiveRecord::Base", Class.new)
    allow(rails).to receive_messages(test_configs: [db])
    allow(rails).to receive(:copy_database) { |source, name| copies << [source, name] }
    allow(rails).to receive(:disconnect)
    allow(described_class).to receive(:memory_database?).and_return(false)
  end

  it "copies nothing for one job, no jobs or without ActiveRecord, and does not disconnect" do
    [1, 0].each { |jobs| rails.prepare_workers(jobs) }
    hide_const("ActiveRecord::Base")
    rails.prepare_workers(3)
    expect(copies).to eq([])
    expect(rails).not_to have_received(:disconnect)
  end

  it "makes one copy per extra worker, named for saboteur, then disconnects once" do
    rails.prepare_workers(2)
    expect(copies).to eq([[db, "app_test_saboteur2"]])
    copies.clear
    rails.prepare_workers(3)
    expect(copies).to eq([[db, "app_test_saboteur2"], [db, "app_test_saboteur3"]])
    expect(rails).to have_received(:disconnect).twice
  end

  it "makes no copy of an in-memory database but still disconnects" do
    allow(described_class).to receive(:memory_database?).with(db).and_return(true)
    rails.prepare_workers(3)
    expect(copies).to eq([])
    expect(rails).to have_received(:disconnect).once
  end

  it "tracks every attempted copy, even when one fails, so cleanup can drop them" do
    allow(rails).to receive(:copy_database) do |_source, name|
      copies << name
      raise "copy failed" if name.end_with?("2")
    end
    expect { rails.prepare_workers(3) }.to raise_error("copy failed")
    expect(rails.instance_variable_get(:@worker_copies)).to eq([[db, "app_test_saboteur2"]])
  end
end
