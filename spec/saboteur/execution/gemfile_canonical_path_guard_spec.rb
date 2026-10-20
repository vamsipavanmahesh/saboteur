# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"

RSpec.describe Saboteur::Execution::GemfilePathSources do
  it "stops climbing at a root that does not exist and returns instead of looping" do
    allow(File).to receive(:exist?).and_return(false)
    path = nil
    Timeout.timeout(5) { path = described_class.canonical_path("no/such/dir") }
    expect(path).to end_with("/no/such/dir")
  end
end
