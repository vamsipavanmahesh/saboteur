# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::SelectionOptions, "run help" do
  let(:help) do
    out = StringIO.new
    Saboteur::CLI.new(%w[run --help], out:, err: StringIO.new).call
    out.string
  end

  {
    "--operators NAMES" => "Choose operator names (default: all)",
    "--exclude-operators NAMES" => "Exclude operator names from the selected set",
    "--list-operators" => "List operator names and descriptions",
    "--dry-run" => "Preview mutants without boot, tests, forks or report writes",
    "--id DIGEST" => "Replay exactly one current mutant by its full digest",
    "--shard K/N" => "Run one of N deterministic candidate shards (for example 1/4)",
    "--since REF" => "Only mutate subjects changed since git REF",
    "--ignore-empty" => "Deprecated no-op: the no-mutant diff case always exits 0 (#1142)",
    "--subject EXPR" => "Klass#meth, Klass.meth or a namespace; repeatable"
  }.each do |switch, description|
    it "describes #{switch.split.first}" do
      line = help.lines.find { |text| text.include?(switch) }
      expect(line.strip).to match(/\A#{Regexp.escape(switch)}\s+#{Regexp.escape(description)}\z/)
    end
  end

  describe "values" do
    def parse(*argv)
      cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
      parser = OptionParser.new
      cli.send(:define_selection_options, parser)
      parser.parse!(argv)
      cli
    end

    it "splits --operators and --exclude-operators into name lists" do
      cli = parse("--operators", "a,b", "--exclude-operators", "c,d")
      expect(cli.options[:operators]).to eq(%w[a b])
      expect(cli.options[:exclude_operators]).to eq(%w[c d])
    end

    it "keeps the --ignore-empty switch ahead of its description in the help" do
      line = help.lines.find { |text| text.include?("--ignore-empty") }
      expect(line).to match(/\A\s*--ignore-empty\s+Deprecated no-op/)
    end

    it "sets --ignore-empty" do
      expect(parse("--ignore-empty").options[:ignore_empty]).to be(true)
    end

    it "collects each --subject expression in order" do
      cli = parse("--subject", "Foo#bar", "--subject", "Baz")
      expect(cli.options[:subjects]).to eq(["Foo#bar", "Baz"])
    end
  end
end
