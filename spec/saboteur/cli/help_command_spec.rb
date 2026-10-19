# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::HelpCommand do
  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Saboteur::CLI.new(argv, out:, err:).call
    [code, out.string, err.string]
  end

  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns help_requested? and show_help, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(:help_requested?, :show_help)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(:help_requested?, :show_help)
  end

  it "prints the overview for help and the command page for help COMMAND" do
    code, out, = cli("help")
    expect(code).to eq(0)
    expect(out).to include("USAGE\n  saboteur <command> [options]")
    code, out, = cli("help", "doctor")
    expect(code).to eq(0)
    expect(out).to include("saboteur doctor")
  end

  it "answers an unknown command with the command list and a usage exit" do
    code, out, err = cli("help", "nope")
    expect(code).to eq(2)
    expect(out).to be_empty
    expect(err).to match(/\Aunknown command: nope\. Commands: .+/)
  end

  it "shows help for -h and --help after any command instead of running it" do
    %w[run baseline doctor badge].each do |command|
      %w[-h --help].each do |flag|
        code, out, = cli(command, flag)
        expect(code).to eq(0)
        expect(out).to include("saboteur #{command}")
      end
    end
  end
end
