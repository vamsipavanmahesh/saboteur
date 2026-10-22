# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::ColorOption do
  def build(*argv) = Saboteur::CLI.new(argv, out: StringIO.new, err: StringIO.new)

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Saboteur::CLI.new(argv, out:, err:).call
    [code, out.string, err.string]
  end

  def color_of(instance) = instance.instance_variable_get(:@color)

  it "is mixed into Saboteur::CLI" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  %i[doctor_parser baseline_parser badge_parser trend_parser].each do |parser|
    describe "##{parser}" do
      it "sets the colour mode from --color, --color=MODE and --no-color" do
        { %w[--color] => :always, %w[--color=never] => :never, %w[--color=auto] => :auto,
          %w[--no-color] => :never }.each do |argv, mode|
          instance = build
          instance.send(parser).parse!(argv.dup)
          expect(color_of(instance)).to eq(mode), "#{parser} #{argv}"
        end
      end

      it "documents --color and the deprecated --no-color alias" do
        text = build.send(parser).help
        expect(text).to include("--color [MODE]", "--no-color", "Deprecated alias for --color=never")
      end
    end
  end

  describe "usage errors name the failing command" do
    {
      "doctor" => :doctor_parser, "baseline" => :baseline_parser, "badge" => :badge_parser,
      "trend" => :trend_parser
    }.each do |command, parser|
      it "prints the #{command} usage line, not run's" do
        code, out, err = cli(*[command, ("check" if command == "baseline"), "--bogus"].compact)
        banner = build.send(parser).banner
        expect(code).to eq(2)
        expect(out).to be_empty
        expect(err).to eq("invalid option: --bogus\n#{banner}\nRun 'saboteur help #{command}' for every option.\n")
        expect(err).not_to include(Saboteur::CLI::USAGE)
      end
    end

    it "keeps run's usage line for commands without their own banner" do
      _, _, err = cli("run", "--bogus")
      expect(err).to end_with("#{Saboteur::CLI::USAGE}\n")
    end
  end

  describe "help and explain consume leading colour switches" do
    it "does not call a colour flag an unknown command" do
      %w[--no-color --color=never --color].each do |flag|
        code, out, err = cli("help", flag)
        expect(code).to eq(0), flag
        expect(out).to include("USAGE")
        expect(err).not_to include("unknown command")
      end
      code, out, = cli("help", "--no-color", "doctor")
      expect(code).to eq(0)
      expect(out).to include("saboteur doctor")
    end

    it "removes the switches from argv so the next word is the command" do
      instance = build("--no-color", "doctor")
      instance.send(:consume_color_options)
      expect(instance.instance_variable_get(:@argv)).to eq(%w[doctor])
      expect(color_of(instance)).to eq(:never)
    end

    it "paints explain only when asked, whatever the stream is" do
      operator = Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys.first.to_s
      _, painted, = cli("explain", "--color=always", operator)
      _, plain, = cli("explain", operator)
      _, never, = cli("explain", "--color=never", operator)
      expect(painted).to include("\e[")
      expect(plain).not_to include("\e[")
      expect(never).not_to include("\e[")
    end

    it "names the operator usage when explain has no operator" do
      code, _, err = cli("explain", "--no-color")
      expect(code).to eq(2)
      expect(err).to eq("saboteur: usage: saboteur explain <operator>\n")
    end
  end
end
