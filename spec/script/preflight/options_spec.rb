# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Options do
  let(:sha) { "a" * 40 }
  let(:valid) { ["--base", sha, "--head", "b" * 40, "--base-ref", "main", "--mode", "fast"] }

  it "accepts full SHAs, main and a known mode (valid control)" do
    expect(described_class.parse(valid).mode).to eq("fast")
  end

  it "rejects an abbreviated SHA" do
    expect { described_class.parse(valid.map { |v| v == sha ? "a" * 7 : v }) }
      .to raise_error(Preflight::InvalidInvocation, /40-character/)
  end

  it "rejects a branch name in place of a SHA" do
    expect { described_class.parse(valid.map { |v| v == sha ? "origin/main" : v }) }
      .to raise_error(Preflight::InvalidInvocation)
  end

  it "rejects uppercase SHAs" do
    expect { described_class.parse(valid.map { |v| v == sha ? "A" * 40 : v }) }
      .to raise_error(Preflight::InvalidInvocation)
  end

  it "rejects a base ref other than main" do
    expect { described_class.parse(valid.map { |v| v == "main" ? "feature" : v }) }
      .to raise_error(Preflight::InvalidInvocation, /main/)
  end

  it "rejects an unknown mode, an unknown option, a missing value and a repeated option" do
    expect { described_class.parse(valid.map { |v| v == "fast" ? "quick" : v }) }.to raise_error(Preflight::InvalidInvocation)
    expect do
      described_class.parse(valid + ["--allow-protected", "x"])
    end.to raise_error(Preflight::InvalidInvocation, /unknown/)
    expect { described_class.parse(valid + ["--mode"]) }.to raise_error(Preflight::InvalidInvocation)
    expect { described_class.parse(valid + ["--mode", "full"]) }.to raise_error(Preflight::InvalidInvocation, /twice/)
  end
end
