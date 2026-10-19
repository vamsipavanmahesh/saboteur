# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::SuitePartition do
  let(:files) { %w[spec/d_spec.rb spec/a_spec.rb spec/c_spec.rb spec/b_spec.rb spec/e_spec.rb] }

  it "deals the sorted files round-robin, as script/rspec-shard does without weights (#741)" do
    expect(described_class.parts(files, 2)).to eq([%w[spec/a_spec.rb spec/c_spec.rb spec/e_spec.rb],
                                                   %w[spec/b_spec.rb spec/d_spec.rb]])
  end

  it "puts every file in exactly one part" do
    parts = described_class.parts(files, 3)

    expect(parts.flatten.sort).to eq(files.sort)
    expect(parts.map(&:size)).to eq([2, 2, 1])
  end

  it "gives the same parts whatever order the files arrive in" do
    expect(described_class.parts(files.reverse, 3)).to eq(described_class.parts(files, 3))
  end

  it "keeps one part holding every file for a total of 1" do
    expect(described_class.parts(files, 1)).to eq([files.sort])
  end

  it "returns no empty part when there are fewer files than parts" do
    expect(described_class.parts(%w[spec/b_spec.rb spec/a_spec.rb], 4)).to eq([%w[spec/a_spec.rb], %w[spec/b_spec.rb]])
  end

  it "returns no parts for no files and counts a repeated file once" do
    expect(described_class.parts([], 3)).to eq([])
    expect(described_class.parts(%w[spec/a_spec.rb spec/a_spec.rb], 2)).to eq([%w[spec/a_spec.rb]])
  end

  it "refuses a total below 1" do
    expect { described_class.parts(files, 0) }.to raise_error(ArgumentError, "parts must be at least 1, got 0")
  end
end
