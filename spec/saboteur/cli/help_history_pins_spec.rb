# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "help and badge error pins" do
  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Saboteur::CLI.new(argv, out: out, err: err).call
    [code, out.string, err.string]
  end

  it "lists the known commands comma separated after an unknown help topic" do
    code, _out, err = cli("help", "nope")
    expect(code).to eq(2)
    names = Saboteur::Help.new(option_lines: []).command_names
    expect(err).to eq("unknown command: nope. Commands: #{names.join(', ')}\n")
  end

  it "does not print help for a command given without --help" do
    allow(Saboteur::Doctor).to receive(:new).and_return(instance_double(Saboteur::Doctor, call: true))
    code, out, = cli("doctor")
    expect(code).to eq(0)
    expect(out).to eq("")
  end

  it "reports a missing history path even when the config cannot be loaded" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure { |c| c.nonsense = 1 }\n")
      Dir.chdir(dir) do
        code, _out, err = cli("badge")
        expect(code).to eq(2)
        expect(err).to include("no score history: pass --history PATH or set c.score_history")
      end
    end
  end
end
