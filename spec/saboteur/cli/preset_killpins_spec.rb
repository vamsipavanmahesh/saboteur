# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"
require "saboteur/cli"

RSpec.describe Saboteur::CLI, "preset banner regression pins" do
  it "keeps only real long flags and the last detached value at its actual index" do
    cli = described_class.new(["file=ignored", "prefix--since=wrong", "--", "--since", "first", "--html",
                               "page.html", "--since", "last", "--json"])
    expect(cli.send(:user_flag_overrides)).to eq(
      "--since" => ["--since", "last"], "--html" => ["--html", "page.html"]
    )
  end

  it "does not turn embedded or empty long-flag names into overrides" do
    cli = described_class.new(["prefix--since=wrong", "--=value"])
    expect(cli.send(:user_flag_overrides)).to eq({})
  end

  it "does not claim operands for flags outside the value-flag list" do
    cli = described_class.new(["--unknown", "operand", "--since=chosen"])
    expect(cli.send(:user_flag_overrides)).to eq("--since" => ["--since=chosen"])
  end

  it "prints each preset value once" do
    cli = described_class.new([])
    expect(cli.send(:preset_banner, ["--since", "origin/main"])).to eq(["--since", "origin/main"])
  end

  it "finishes even for a dangling preset value flag" do
    cli = described_class.new([])
    banner = Timeout.timeout(0.2) { cli.send(:preset_banner, ["--since"]) }
    expect(banner).to eq(["--since", nil])
  end
end
