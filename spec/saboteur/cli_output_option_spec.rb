# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "Saboteur::CLI --format option" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    Saboteur::CLI.new(argv, out: out, err: err)
  end

  it "documents all three formats and that json is the --dry-run inventory" do
    expect(cli("run", "--help").call).to eq(0)
    expect(out.string).to include("--format FORMAT")
    expect(out.string).to include("text, agent or json (--dry-run inventory)")
  end

  it "accepts --format text with --dry-run and prints the text inventory" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "widget.rb"), "class Widget\n  def m(x)\n    x + 1\n  end\nend\n")
      Dir.chdir(root) do
        expect(cli("run", "--dry-run", "--format", "text").call).to eq(0)
      end
    end
    expect(err.string).not_to include("invalid argument")
    expect(out.string).to start_with("Operators: ")
    expect(out.string).to include("Total: ")
    expect { JSON.parse(out.string) }.to raise_error(JSON::ParserError)
  end

  it "rejects an unknown --format value" do
    expect(cli("run", "--dry-run", "--format", "yaml").call).to eq(2)
    expect(err.string).to include("invalid argument")
  end
end
