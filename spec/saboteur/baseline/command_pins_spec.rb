# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/cli"

RSpec.describe "baseline CLI pins" do
  # A hash the parser wrongly accepts must stop here, not start a nested
  # saboteur run inside this suite.
  before { allow(Saboteur::Baseline::Workflow).to receive(:new).and_raise("workflow reached") }

  def run_baseline(*args)
    @err = StringIO.new
    Saboteur::CLI.new(["baseline", *args], out: StringIO.new, err: @err).call
  end

  { "text before the digits" => "junk#{'a' * 64}", "text after the digits" => "#{'a' * 64}junk" }.each do |name, value|
    it "rejects a --previous hash with #{name}" do
      expect(run_baseline("propose", "--baseline", "b.json", "--proposal", "p.json", "--previous", value)).to eq(2)
      expect(@err.string.lines.first).to eq("saboteur: --previous needs a SHA-256\n")
    end
  end

  it "lists the --format description in the option help" do
    help = Saboteur::CLI.new(["baseline"]).baseline_parser.help
    expect(help).to include("--format FORMAT")
    expect(help).to include("propose: terminal (default) or json")
  end

  it "lists the full epsilon description in the option help" do
    help = Saboteur::CLI.new(["baseline"]).baseline_parser.help
    expect(help).to include("check: also fail when the score drops more than POINTS " \
                            "percentage points below the baseline's")
  end
end
