# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  it "invokes after_subject with each subject's results in serial" do
    scheduler = ->(subject, list) { [subject, list] }
    seen = []
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil,
                                       after_subject: ->(subject, results) { seen << [subject, results] })
    distribution.run(%i[a b], [["la"], ["lb"]])
    expect(seen).to eq([[:a, [:a, ["la"]]], [:b, [:b, ["lb"]]]])
  end

  it "runs serial without an after_subject callback" do
    scheduler = ->(subject, _list) { [subject] }
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    expect(distribution.run(%i[a], [[]])).to eq([:a])
  end

  it "uses the worker pool when jobs is above one" do
    scheduler = ->(subject, _list) { [subject] }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    allow(Saboteur::Execution::WorkerPool).to receive(:new).and_raise(Saboteur::Error, "pool started")
    expect { distribution.run(%i[a], [[]]) }.to raise_error(Saboteur::Error, "pool started")
  end
end
