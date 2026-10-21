# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI, "first-run hints" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv) = described_class.new(argv, out:, err:)

  it "tells a bare saboteur what to run next, before the usage line" do
    expect(cli.call).to eq(2)
    expect(err.string).to start_with(
      "saboteur: no command given. New here? saboteur init writes a starter config; " \
      "saboteur doctor checks the setup\nUsage: saboteur run"
    )
  end

  it "names an unknown command instead of only printing the usage" do
    expect(cli("runn").call).to eq(2)
    expect(err.string).to start_with("saboteur: unknown command \"runn\"; saboteur help lists the commands\n")
  end

  it "keeps the agent payload on the plain usage text" do
    cli("runn", "--agent").call
    expect(JSON.parse(out.string)["message"]).to eq(described_class::USAGE)
  end
end
