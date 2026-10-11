# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "yaml"

# The help text is the map an AI agent reads instead of the docs. These specs
# keep it complete: a new option, command, config key or exit code that is not
# in the help text fails here.
RSpec.describe Saboteur::Help do
  let(:cli) { Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new) }
  let(:help) { described_class.new(option_lines: cli.option_lines) }
  let(:overview) { help.overview }

  it "has the sections an agent looks for, in a fixed order" do
    headers = overview.lines.grep(/\A[A-Z][A-Z ]+( \(.*\))?\n\z/).map(&:strip)
    expect(headers).to eq(["USAGE", "COMMANDS", "OPTIONS (saboteur run)", "EXAMPLES", "EXIT CODES",
                           "CONFIG FILE (.saboteur.yml)", "FILES"])
  end

  it "starts with the name, the version and a one-line purpose" do
    expect(overview.lines.first).to eq("saboteur #{Saboteur::VERSION} - mutation testing for Ruby and RSpec\n")
  end

  it "lists every public option of the parser with its description" do
    cli.parser.top.list.each do |switch|
      (switch.long + switch.short).each { |flag| expect(overview).to include(flag) }
      switch.desc.each { |description| expect(overview).to include(description) }
    end
  end

  it "lists every command" do
    described_class::COMMANDS.each do |command|
      expect(overview).to match(/^  #{command.name}\s+#{Regexp.escape(command.summary)}$/)
    end
  end

  it "lists every config key with its exact default, as YAML that loads back to the same value" do
    Saboteur::Config::DEFAULTS.each do |key, default|
      line = overview.lines.find { |candidate| candidate.start_with?("  #{key}: ") }
      expect(line).not_to be_nil
      expect(YAML.safe_load(line.delete_prefix("  #{key}: "))).to eq(default)
    end
  end

  it "does not promise that nothing runs for a usage or configuration error" do
    expect(overview).not_to include("Nothing was run")
  end

  it "lists every exit code" do
    %w[EXIT_OK EXIT_SURVIVORS EXIT_USAGE EXIT_TOOL].each do |name|
      expect(overview).to match(/^  #{Saboteur::CLI.const_get(name)}  \S/)
    end
  end

  it "gives examples that start with saboteur and use only real commands and options" do
    section = overview[/^EXAMPLES\n(.*?)\n\n/m, 1]
    examples = section.lines.grep(/\A  saboteur /).map(&:strip)
    expect(examples.size).to be >= 3
    examples.each do |example|
      words = example.split(/\s+(?=(?:[^']*'[^']*')*[^']*\z)/).map { |word| word.delete("'") }
      name = words[1]
      expect(described_class::COMMANDS.map(&:name)).to include(name)
      parse_options(words.drop(2)) if name == "run"
    end
  end

  it "describes one command in detail" do
    text = help.command("run")
    expect(text).to include("USAGE").and include("saboteur run [options]").and include("--since REF")
    expect(text).to include("EXAMPLES").and include("EXIT CODES")
  end

  it "does not list options for a command that takes none" do
    expect(help.command("version")).not_to include("--since")
  end

  it "gives a command without options a bare usage line and no exit codes section" do
    text = help.command("version")
    expect(text).to include("USAGE\n  saboteur version\n")
    expect(text).not_to include("[options]")
    expect(text).not_to include("EXIT CODES")
  end

  it "gives a command with options an [options] usage line and an exit codes section" do
    text = help.command("run")
    expect(text).to include("USAGE\n  saboteur run [options]\n")
    expect(text).to include("EXIT CODES\n  0  ")
  end

  it "sets the usage text as the option parser's banner" do
    expect(cli.parser.banner).to eq(Saboteur::CLI::USAGE)
  end

  describe "--threshold exit semantics" do
    let(:exit_rows) { overview[/^EXIT CODES\n(.*?)\n\n/m, 1].gsub("\n    ", " ") }

    def row(code)
      exit_rows.lines.find { |line| line.start_with?("  #{code}  ") }
    end

    it "says exit 0 allows survivors when the score meets the threshold" do
      expect(row(0)).to include("Without --threshold: no unignored survivors")
      expect(row(0)).to include("With --threshold: the score is at or above it, even if mutants survived")
    end

    it "says --threshold replaces the survivor gate for exit 1, and a missing score fails" do
      expect(row(1)).to include("Without --threshold: at least one mutant survived")
      expect(row(1)).to include("survivors alone no longer fail the run")
      expect(row(1)).to include("below it, or no mutant was tested")
    end

    it "describes --threshold as a pass/fail gate, not as the exit code itself" do
      description = described_class::COMMANDS.first.description
      expect(description).to include("replaces the survivor check")
      expect(description).not_to include("makes the score the exit code")
    end
  end

  it "returns nil for a command it does not know" do
    expect(help.command("explode")).to be_nil
  end

  def parse_options(arguments)
    Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new).parser.parse!(arguments.dup)
  end
end
