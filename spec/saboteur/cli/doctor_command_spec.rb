# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::DoctorCommand do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the doctor parser and command, moved out of CLI itself" do
    expect(described_class.public_instance_methods(false)).to include(:doctor_parser)
    expect(described_class.private_instance_methods(false)).to include(:doctor, :doctor_command)
    expect(Saboteur::CLI.public_instance_methods(false)).not_to include(:doctor_parser)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(:doctor, :doctor_command)
  end

  # The extraction moved the option table verbatim; pin every line so a
  # swapped or emptied help string cannot survive the dogfood (#754).
  describe "doctor --help and argument handling" do
    def cli(*argv)
      out = StringIO.new
      err = StringIO.new
      code = Saboteur::CLI.new(argv, out:, err:).call
      [code, out.string, err.string]
    end

    # Flag and help text must be pinned as an adjacent pair: separately they
    # both still appear after an argument_swap, which the dogfood proved.
    it "prints every doctor option with its help text" do
      code, out, = cli("doctor", "--help")
      expect(code).to eq(0)
      {
        "--config PATH" => "Config file (default config/saboteur.rb)",
        "--seed N" => "Seed for the two baseline runs (default 1)",
        "--suite" => "Also run the unchanged suite twice (slow on a large suite)",
        "--test PATH" => "Spec file or directory for the suite runs; repeatable. Implies --suite",
        "-v, --verbose" => "Full environment detail instead of the summary",
        "--color [MODE]" => "Colour the summary: always, never or auto (default: auto)"
      }.each do |flag, help|
        expect(out).to match(/#{Regexp.escape(flag)}\s+#{Regexp.escape(help)}/), "no help text after #{flag}"
      end
    end

    it "rejects extra arguments, naming all of them" do
      code, _, err = cli("doctor", "a", "b")
      expect(code).to eq(2)
      expect(err).to include("unexpected arguments: a b")
    end
  end
end
