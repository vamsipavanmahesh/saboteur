# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration do
  it "registers the rspec adapter, and only it (Minitest is out of scope)" do
    expect(described_class.fetch(:rspec)).to eq(Saboteur::Integration::RSpec)
    expect(described_class::REGISTRY.keys).to eq(["rspec"])
    expect { described_class.fetch(:minitest) }.to raise_error(Saboteur::Error, /unknown integration/)
  end

  it "raises a saboteur error for an unknown adapter" do
    expect { described_class.fetch(:cucumber) }.to raise_error(Saboteur::Error, /unknown integration/)
  end

  it "requires adapters to implement the contract" do
    adapter = described_class::Base.new({})
    %i[setup all_tests].each { |m| expect { adapter.public_send(m) }.to raise_error(NotImplementedError) }
    expect { adapter.run([]) }.to raise_error(NotImplementedError)
    expect { adapter.run_all(nil) }.to raise_error(NotImplementedError)
    expect(adapter.test_files).to eq([])
  end
end
