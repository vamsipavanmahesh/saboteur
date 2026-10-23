# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1332: a statement's surviving mutants can carry different labels - a
# no-op arithmetic change is input_gap, a value-changing sibling is
# assertion_gap. The terminal block, the default findings list and the
# --quiet line all speak for the mutant CARRYING the statement's label, so
# the shown diff and digest match that mutant's own JSON record.
# #1334: the agent JSON findings show `classification` only; `kind` and
# `gapKind` live in report.json and the Action findings payload.
RSpec.describe "the survivor shown for a statement carries the statement's label", :e2e do
  let(:dir) { copy_fixture("people") }

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def mutants_on(run, subject)
    mutants(run).select { |m| m["subject"] == subject }
  end

  before do
    # One statement, two survivor classes: dropping ` + 0` never produces a
    # different value (input_gap), and it ranks FIRST among the statement's
    # survivors for this source; the number changes do produce one
    # (assertion_gap), because the spec only pins positivity. The label
    # carrier is therefore never the ranked-first mutant here.
    write("lib/fee.rb", <<~RUBY)
      class Fee
        def self.exact(amount) = amount * 6 + 0
      end
    RUBY
    write("spec/fee_spec.rb", <<~RUBY)
      require_relative "../lib/fee"

      RSpec.describe Fee do
        it("stays positive") { expect(described_class.exact(5)).to be_positive }
      end
    RUBY
  end

  it "shows the diff of the mutant carrying the label, with a mixed-label sibling group (#1332)" do
    run = saboteur(dir, "--all")
    expect(run.status).to eq(1), run.err

    survivors = mutants_on(run, "Fee.exact").select { |m| m["status"] == "Survived" }
    expect(survivors.map { |m| m["classification"] }).to include("input_gap", "assertion_gap")

    lines = run.out.lines
    header = lines.index { |line| line.include?("Fee.exact") && line.include?("assertion gap") }
    expect(header).not_to be_nil, run.out
    block = lines[header..].take_while { |line| !line.strip.empty? }
    pair = block.find { |line| line =~ /^\+\s+\d+.*· ([0-9a-f]{16})/ }
    expect(pair).not_to be_nil, block.join
    shown = survivors.find { |m| m["id"] == pair[/([0-9a-f]{16})/] }
    expect(shown).to include("classification" => "assertion_gap", "valueDiffered" => true)
  end

  it "names the label-carrying digest in the findings list and under --quiet (#1332)" do
    run = saboteur(dir, "--all")
    listed = run.out.lines.find { |line| line.include?("Fee.exact [assertion_gap] - ") }
    expect(listed).not_to be_nil, run.out
    digest = listed[/\[assertion_gap\] - ([0-9a-f]{16})/, 1]
    shown = mutants_on(run, "Fee.exact").find { |m| m["id"] == digest }
    expect(shown).to include("classification" => "assertion_gap", "valueDiffered" => true)

    quiet = saboteur(dir, "--all", "--quiet")
    line = quiet.out.lines.find { |entry| entry.include?("Fee.exact [assertion_gap] - ") }
    expect(line).not_to be_nil, quiet.out
    quiet_digest = line[/\[assertion_gap\] - ([0-9a-f]{16})/, 1]
    quiet_shown = mutants_on(quiet, "Fee.exact").find { |m| m["id"] == quiet_digest }
    expect(quiet_shown).to include("classification" => "assertion_gap", "valueDiffered" => true)
  end

  it "shows classification alone in the agent JSON findings (#1334)" do
    run = saboteur(dir, "--all", "--agent")

    shown = JSON.parse(run.out).dig("findings", "shown")
    expect(shown).not_to be_empty
    shown.each do |finding|
      expect(finding).to include("classification")
      expect(finding.keys & %w[kind gapKind]).to be_empty
    end
  end
end
