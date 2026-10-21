# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The help text is the map an AI agent reads instead of the docs. These specs
# keep it complete: a new option, command, config key or exit code that is not
# in the help text fails here.
RSpec.describe Saboteur::Help do
  let(:cli) { Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new) }
  let(:help) { described_class.new(option_lines: cli.option_lines) }
  let(:overview) { help.overview }

  describe "exact layout" do
    let(:commands) { described_class::COMMANDS }
    let(:name_width) { commands.map { |command| command.name.length }.max }

    it "opens with the title and closes with the documentation link on their own lines" do
      expect(overview).to start_with("saboteur #{Saboteur::VERSION} - #{described_class::PURPOSE}\n\nUSAGE\n")
      expect(overview).to end_with("\n\nDocumentation: #{described_class::DOCUMENTATION}\n")
    end

    it "pads every command name to the longest one and ends the section with a blank line" do
      rows = commands.map { |command| "  #{command.name.ljust(name_width)}  #{command.summary}" }
      expect(overview).to include("\nCOMMANDS\n#{rows.join("\n")}\n\nOPTIONS (saboteur run)\n")
    end

    it "pads every file path to the longest one, one row per line, before the documentation link" do
      width = described_class::FILES.map { |path, _| path.length }.max
      rows = described_class::FILES.map { |path, meaning| "  #{path.ljust(width)}  #{meaning}" }
      expect(overview).to include("\nFILES\n#{rows.join("\n")}\n\nDocumentation: ")
    end

    it "separates the config intro, the settings and the files section with newlines" do
      intro = "Every setting with its default value, as a Ruby assignment. Unknown settings are an error."
      rows = Saboteur::Config::DEFAULTS.map { |key, value| "  c.#{key} = #{value.inspect}" }
      expect(overview).to include("\nCONFIG FILE (config/saboteur.rb)\n#{intro}\n#{rows.join("\n")}\n\nFILES\n")
    end
  end

  it "has the sections an agent looks for, in a fixed order" do
    headers = overview.lines.grep(/\A[A-Z][A-Z ]+( \(.*\))?\n\z/).map(&:strip)
    expect(headers).to eq(["USAGE", "COMMANDS", "OPTIONS (saboteur run)", "OPTIONS (saboteur pr)",
                           "OPTIONS (saboteur audit)", "OPTIONS (saboteur doctor)",
                           "OPTIONS (saboteur init)",
                           "OPTIONS (saboteur baseline)", "OPTIONS (saboteur badge)", "OPTIONS (saboteur trend)",
                           "EXAMPLES",
                           "EXIT CODES (saboteur run)", "EXIT CODES (saboteur pr)", "EXIT CODES (saboteur audit)",
                           "EXIT CODES (saboteur doctor)", "EXIT CODES (saboteur init)",
                           "EXIT CODES (saboteur baseline)", "EXIT CODES (saboteur survivors)",
                           "EXIT CODES (saboteur badge)", "EXIT CODES (saboteur trend)",
                           "CONFIG FILE (config/saboteur.rb)", "FILES"])
  end

  describe "the generated CONFIG FILE section" do
    let(:section) { overview[%r{^CONFIG FILE \(config/saboteur\.rb\)\n(.*?)\nFILES\n}m, 1] }

    it "introduces the section" do
      expect(section).to include("Every setting with its default value, as a Ruby assignment. " \
                                 "Unknown settings are an error.")
    end

    it "prints nil, never JSON null, for the unset defaults" do
      expect(section).to include("c.since = nil")
      expect(section).not_to include("null")
    end
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

  it "explains --allow-focus in words an agent can act on" do
    expect(overview).to include("--allow-focus").and include("Run even when a focus filter")
    expect(overview).to include("fit, fdescribe, :focus")
  end

  it "lists every switch of the doctor parser with its description" do
    cli.doctor_parser.top.list.each do |switch|
      (switch.long + switch.short).each { |flag| expect(overview).to include(flag) }
      switch.desc.each { |description| expect(overview).to include(description) }
    end
  end

  it "has an options section and an exit codes section for every command that takes options" do
    described_class::COMMANDS.select(&:takes_options).each do |command|
      expect(overview).to include("OPTIONS (saboteur #{command.name})")
      expect(overview).to include("EXIT CODES (saboteur #{command.name})")
    end
  end

  it "appends the stricter --agent exit code note to the general exit codes (#245)" do
    section = overview[/^EXIT CODES \(saboteur run\)\n(.*?)(?=\n[A-Z]|\z)/m, 1]
    expect(section).to include(described_class::AGENT_EXIT_CODES)
    expect(overview).to include("#{described_class::AGENT_EXIT_CODES}\n\n")
  end

  it "lists the doctor exit codes under the doctor heading" do
    section = overview[/^EXIT CODES \(saboteur doctor\)\n(.*?)\n\n/m, 1]
    expect(section.lines.map(&:strip)).to eq(described_class::DOCTOR_EXIT_CODE_MEANINGS.map { |c, m| "#{c}  #{m}" })
  end

  it "documents the preset flag bundles and the budget exit code (#244, #245)" do
    expect(help.command("pr")).to include("--baseline-passes 1 --max-duration 10m")
    expect(help.command("audit")).to include("--json .saboteur/audit-report.json")
    expect(help.command("audit")).to include("--html .saboteur/audit-report.html")
    expect(overview).to include("  4  Time budget spent: --max-duration stopped the run")
  end

  it "documents the cache dir as safe to delete between runs, not mid-run (#300)" do
    expect(overview).to include(".saboteur/", "Safe to delete between runs; stop the run first")
  end

  it "states that doctor certifies no external tool versions (#318)" do
    expect(help.command("doctor")).to include("certifies no versions of Rails, databases or tools")
  end

  it "lists every command" do
    described_class::COMMANDS.each do |command|
      expect(overview).to match(/^  #{command.name}\s+#{Regexp.escape(command.summary)}$/)
    end
  end

  it "lists every config setting with its exact default, as a Ruby assignment that loads back to the same value" do
    assignments = Saboteur::Config::DEFAULTS.map do |key, _|
      line = overview.lines.find { |candidate| candidate.start_with?("  c.#{key} = ") }
      expect(line).not_to be_nil
      line
    end
    Dir.mktmpdir do |root|
      path = File.join(root, "config", "saboteur.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "Saboteur.configure do |c|\n#{assignments.join}end\n")
      loaded = Saboteur::Config.load(root: root, path: path)
      Saboteur::Config::DEFAULTS.each do |key, default|
        expect(loaded[key]).to eq(default), "c.#{key} did not load back to its default"
      end
    end
  end

  it "does not promise that nothing runs for a usage or configuration error" do
    expect(overview).not_to include("Nothing was run")
  end

  it "lists every exit code" do
    %w[EXIT_OK EXIT_SURVIVORS EXIT_USAGE EXIT_TOOL EXIT_BASELINE_RED EXIT_CRASH].each do |name|
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

  it "describes badge and trend with the exact rendered text (#474)" do
    badge_help = "saboteur badge - Print a shields.io endpoint badge over the opt-in score history\n" \
                 "\n" \
                 "Reads the score history JSONL (c.score_history, or --history PATH) and prints one " \
                 "shields.io endpoint badge JSON for the latest record: label, mutation score and color " \
                 "(brightgreen at or above --high, default 80; yellow at or above --low, default 60; " \
                 "red below). --output PATH writes the file instead of printing. An incomplete latest " \
                 "record is refused unless --mark-partial labels the badge as partial. No hosted " \
                 "service, no project boot, no tests run.\n" \
                 "\n" \
                 "USAGE\n  " \
                 "saboteur badge [options]\n" \
                 "\n" \
                 "OPTIONS (saboteur badge)\n        " \
                 "--history PATH               Score history JSONL (default: c.score_history)\n        " \
                 "--output PATH                Badge JSON destination (default: stdout)\n        " \
                 "--mark-partial               Badge an incomplete run, labeled as partial\n        " \
                 "--high PERCENT               brightgreen at or above (default 80)\n        " \
                 "--low PERCENT                yellow at or above (default 60)\n" \
                 "\n" \
                 "EXAMPLES\n  " \
                 "# Badge the recorded score\n  " \
                 "saboteur badge\n  " \
                 "# Write the badge file CI uploads\n  " \
                 "saboteur badge --output .saboteur/badge.json\n" \
                 "\n" \
                 "EXIT CODES\n  " \
                 "0  Badge JSON written.\n  " \
                 "2  No history path or unexpected arguments.\n  " \
                 "3  Empty or unreadable history, an incomplete record without --mark-partial, or no " \
                 "tested mutants.\n"
    trend_help = "saboteur trend - Print the score trend over the opt-in score history\n" \
                 "\n" \
                 "Reads the score history JSONL (c.score_history, or --history PATH) and prints the " \
                 "latest record next to the most recent comparable one (same configured selection, " \
                 "operator policy and a complete run), with the covered-score change in percentage " \
                 "points. With no comparable earlier record it says so instead of inventing a delta. No " \
                 "hosted service, no project boot, no tests run.\n" \
                 "\n" \
                 "USAGE\n  " \
                 "saboteur trend [options]\n" \
                 "\n" \
                 "OPTIONS (saboteur trend)\n        " \
                 "--history PATH               Score history JSONL (default: c.score_history)\n" \
                 "\n" \
                 "EXAMPLES\n  " \
                 "# Show the latest score and its change\n  " \
                 "saboteur trend\n" \
                 "\n" \
                 "EXIT CODES\n  " \
                 "0  Trend printed.\n  " \
                 "2  No history path or unexpected arguments.\n  " \
                 "3  Empty or unreadable history.\n"
    expect(help.command("badge")).to eq(badge_help)
    expect(help.command("trend")).to eq(trend_help)
  end

  it "describes one command in detail" do
    text = help.command("run")
    expect(text).to include("USAGE").and include("saboteur run [options]").and include("--since REF")
    expect(text).to include("EXAMPLES").and include("EXIT CODES")
  end

  it "describes --all and the --guess-tests alias in the run help" do
    expect(help.command("run")).to include("--all", "Run the whole configured test suite instead of inferring " \
                                                    "the specs named after the mutated files")
    expect(help.command("run")).to include("--[no-]guess-tests", "Deprecated alias: inferred specs are already " \
                                                                 "the default; --no-guess-tests warns and is " \
                                                                 "ignored - use --all for the whole suite")
  end

  it "describes --test-command in the run help (#140)" do
    expect(help.command("run")).to include("--test-command CMD", "exit 0 means the mutant survived")
  end

  it "does not list options for a command that takes none" do
    expect(help.command("version")).not_to include("--since")
  end

  describe "saboteur help doctor" do
    let(:text) { help.command("doctor") }

    it "lists every switch of the doctor parser with its description" do
      expect(text).to include("OPTIONS (saboteur doctor)").and include("saboteur doctor [options]")
      cli.doctor_parser.top.list.each do |switch|
        (switch.long + switch.short).each { |flag| expect(text).to include(flag) }
        switch.desc.each { |description| expect(text).to include(description) }
      end
    end

    it "does not leak run-only switches" do
      flags = ->(parser) { parser.top.list.flat_map(&:long) }
      run_only = flags.call(cli.parser) - flags.call(cli.doctor_parser)
      expect(run_only).to include("--since", "--id")
      run_only.each { |flag| expect(text).not_to match(/#{Regexp.escape(flag)}(?![\w-])/) }
    end

    it "has its own exit codes, not the run ones" do
      expect(text).to include("EXIT CODES\n  0  Healthy")
      expect(text).not_to include("unignored survivors")
    end
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
    let(:exit_rows) { overview[/^EXIT CODES \(saboteur run\)\n(.*?)\n\n/m, 1].gsub("\n    ", " ") }

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
