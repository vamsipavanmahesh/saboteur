# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::CLI, "error messages with repository-controlled names" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:hostile) { "x\n::error::injected.rb" }

  def cli(*argv) = described_class.new(argv, out:, err:)

  def command_lines(text) = text.lines.map(&:strip)

  it "does not print a workflow command line when doctor reports a bad name" do
    allow(Saboteur::Doctor).to receive(:new).and_raise(Saboteur::ConfigError, "bad #{hostile}")
    expect(cli("doctor").call).to eq(2)
    expect(err.string).to include("\\x3a:error::injected.rb")
    expect(command_lines(err.string).grep(/\A(::|##\[)/)).to be_empty
  end

  it "escapes a ConfigError raised during a run, on stderr and in the agent report" do
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::ConfigError, "bad #{hostile}\n##[warning]more")
    status = cli("run", "--format", "agent").call
    expect(status).to eq(2)
    expect(command_lines(err.string + out.string).grep(/\A(::|##\[)/)).to be_empty
    expect(err.string).to include("\\x3a:error::injected.rb")
  end

  it "escapes a tool error raised during a run" do
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "tool #{hostile}")
    expect(cli("run").call).to eq(3)
    expect(command_lines(err.string).grep(/\A(::|##\[)/)).to be_empty
  end
end
