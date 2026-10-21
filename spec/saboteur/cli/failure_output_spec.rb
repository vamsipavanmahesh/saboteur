# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

RSpec.describe Saboteur::CLI::FailureOutput do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv) = Saboteur::CLI.new(argv, out:, err:)

  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the failure sinks, moved out of CLI itself" do
    owned = %i[usage_error agent? agent_failure report_failure]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end

  it "prints the message and the usage on stderr and exits 2" do
    code = cli("run", "--bogus").call
    expect(code).to eq(2)
    expect(err.string).to eq("invalid option: --bogus\n#{Saboteur::CLI::USAGE}\n")
    expect(out.string).to be_empty
  end

  it "falls back to auto colour detection for usage errors when no colour mode is set" do
    allow(Saboteur::Reporter::Palette).to receive(:for).and_call_original

    cli.send(:usage_error, "invalid option: --bogus")

    expect(Saboteur::Reporter::Palette).to have_received(:for).with(err, mode: :auto)
  end

  it "prints only the usage when no message is given" do
    expect(cli.send(:usage_error)).to eq(2)
    expect(err.string).to eq("#{Saboteur::CLI::USAGE}\n")
  end

  it "answers an agent on stdout with the same failure and exit code" do
    code = cli("run", "--agent", "--bogus").call
    expect(code).to eq(2)
    expect(JSON.parse(out.string)).to include("exitCode" => 2, "status" => "error")
    expect(out.string).to include("invalid option: --bogus")
  end

  it "gives an agent the usage as the message when no message is given" do
    run = cli("--format", "agent")
    expect(run.send(:usage_error)).to eq(2)
    expect(JSON.parse(out.string)).to include("message" => Saboteur::CLI::USAGE, "exitCode" => 2)
  end

  it "stays silent on stdout when the run is not in agent mode" do
    expect(cli.send(:agent_failure, "boom", 3)).to eq(3)
    expect(out.string).to be_empty
  end

  it "breaks a workflow command after a newline in an error message, on stderr and in agent mode" do
    run = cli("--format", "agent")
    code = run.send(:report_failure, Saboteur::Error.new("bad x\n::error::y"), 3)
    expect(code).to eq(3)
    expect(err.string).to eq("saboteur: bad x\n\\x3a:error::y\n")
    expect(JSON.parse(out.string)).to include("message" => "bad x\n\\x3a:error::y", "exitCode" => 3)
  end

  it "paints the usage error message with the fail token when colour is on" do
    run = cli("run")
    run.instance_variable_set(:@color, :always)
    run.send(:usage_error, "invalid option: --bogus")
    expect(err.string).to include("\e[31;1minvalid option: --bogus\e[0m")
  end

  it "paints the failure message with the fail token when colour is on" do
    run = cli("run")
    run.instance_variable_set(:@color, :always)
    run.send(:report_failure, Saboteur::Error.new("broken config"), 3)
    expect(err.string).to include("\e[31;1msaboteur: broken config\e[0m")
  end
end
