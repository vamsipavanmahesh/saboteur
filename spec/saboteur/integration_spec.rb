# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration do
  it "registers the rspec adapter, and only it (Minitest is out of scope)" do
    expect(described_class.fetch(:rspec)).to eq(Saboteur::Integration::RSpec)
    expect(described_class::REGISTRY.keys).to eq(["rspec"])
    expect { described_class.fetch(:minitest) }.to raise_error(Saboteur::Error, /unknown integration/)
  end

  it "raises a saboteur error for an unknown adapter" do
    expect { described_class.fetch(:cucumber) }
      .to raise_error(Saboteur::Error, "unknown integration: cucumber")
  end

  it "provides an additive baseline fallback for existing adapters" do
    adapter = described_class::Base.new({})
    tests = [described_class::TestCase.new(id: "t1", file: "spec/a.rb")]
    result = described_class::RunResult.new(passed: true, failed_ids: [], executed_ids: ["t1"], runtime: 0.1)
    allow(adapter).to receive(:all_tests).and_return(tests)
    expect(adapter).to receive(:run).with(["t1"]).and_return(result)
    expect(adapter.run_baseline(seed: 42)).to equal(result)
  end

  it "refuses to run a part of the suite for an adapter that cannot split it" do
    adapter = described_class::Base.new({})
    expect { adapter.run_baseline(seed: 42, files: ["spec/a.rb"]) }
      .to raise_error(NotImplementedError, "Saboteur::Integration::Base cannot run a part of the suite " \
                                           "(files: [\"spec/a.rb\"])")
  end

  it "seeds the random generator before the baseline fallback runs the suite" do
    adapter = described_class::Base.new({})
    drawn = nil
    allow(adapter).to receive(:all_tests).and_return([])
    allow(adapter).to receive(:run) { drawn = Kernel.rand }
    adapter.run_baseline(seed: 42)
    expect(drawn).to eq(Random.new(42).rand)
  end

  it "requires adapters to implement the contract" do
    adapter = described_class::Base.new({})
    %i[setup all_tests].each { |m| expect { adapter.public_send(m) }.to raise_error(NotImplementedError) }
    expect { adapter.run([]) }.to raise_error(NotImplementedError)
    expect { adapter.run_all(nil) }.to raise_error(NotImplementedError)
    expect(adapter.test_files).to eq([])
  end
end
