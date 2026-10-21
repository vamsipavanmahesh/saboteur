# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::DoctorCommand, "option values" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    Saboteur::CLI.new(argv, out:, err:)
  end

  before { allow(Saboteur::Doctor).to receive(:new).and_return(instance_double(Saboteur::Doctor, call: true)) }

  it "gives the doctor parser its exact usage banner" do
    expect(cli("doctor").doctor_parser.banner).to eq(
      "Usage: saboteur doctor [--config PATH] [--seed N] [--suite] [--test PATH] [-v] [--color [MODE]]"
    )
  end

  it "stores the --config path, the integer --seed and the --suite flag under their own keys" do
    command = cli("doctor", "--config", "custom.rb", "--seed", "7", "--suite")
    command.doctor_parser.parse!(command.instance_variable_get(:@argv))
    expect(command.send(:options)).to eq({ config: "custom.rb", seed: 7, suite: true })
  end

  it "rejects a non-integer --seed" do
    expect(cli("doctor", "--seed", "x").call).to eq(2)
  end

  it "prefixes a usage error with saboteur:" do
    expect(cli("doctor", "--test", "spec/nope_spec.rb").call).to eq(2)
    expect(err.string).to start_with("saboteur: ")
  end
end
