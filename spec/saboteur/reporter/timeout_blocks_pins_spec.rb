# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# --with-timeouts (#9b): every timeout renders as a full finding block
# through the same renderer as a survivor block, with the [timeout]
# marker and a closing replay command as the only differences; the 9a
# tally stays the default. Monochrome goldens pin the layout byte for
# byte; the colour pass pins the palette tokens.
RSpec.describe "the --with-timeouts finding blocks (#9b)" do
  after { FileUtils.rm_rf(@dirs.to_a) }

  let(:out) { StringIO.new }

  def dir
    @dirs ||= []
    @dirs << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-pins-")))
    @dir
  end

  def timeout_result(source, name:, from:, to:, operator:, reason: "exceeded 2.0 s", status: :timeout)
    path = File.join(dir, name)
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index(from, subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.size,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status:,
                               mutated_source: subject.apply(mutation.edits), reason:)
  end

  let(:invoice) do
    timeout_result("class Invoice\n  def recalculate\n    @total = 1\n  end\nend\n",
                   name: "invoice.rb", from: "1", to: "2", operator: "literal_number")
  end
  let(:cart) do
    timeout_result("class Cart\n  def total\n    @items.sum.round(2)\n  end\nend\n",
                   name: "cart.rb", from: ".round(2)", to: "", operator: "operand_replacement")
  end

  def render(results, **options)
    out.truncate(0)
    out.rewind
    root = File.dirname(results.first.subject.file)
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.25, root:,
                                  warnings: [], seed: 1)
    Saboteur::Reporter::Terminal.new(out, **options).call(report)
    out.string
  end

  it "renders every timeout as a full finding block under one group header, monochrome" do
    text = render([invoice, cart], with_timeouts: true)
    expect(text).to include(<<~TEXT)
      Timeouts (2):

      1. cart.rb:3 Cart#total [timeout]
          2 def total
      -   3     @items.sum.round(2)
      +   3     @items.sum   operand_replacement · 76a4a25dd1f208ee
                          ^
          4   end
        why it matters: the result no longer depends on the replaced operand
        replay this timeout: saboteur run --id 76a4a25dd1f208ee --seed 1

      2. invoice.rb:3 Invoice#recalculate [timeout]
          2 def recalculate
      -   3     @total = 1
      +   3     @total = 2   literal_number · 1581cbb9e9044712
                         ^
          4   end
        why it matters: no test depends on this exact number
        → try asserting something that depends on this number
        replay this timeout: saboteur run --id 1581cbb9e9044712 --seed 1
    TEXT
    # One group header, no per-line tally entries under it (DX panel, C5).
    expect(text).to include("Timeouts (2):
")
    expect(text).not_to include("cart.rb:3 Cart#total (operand_replacement, deadline 2s)")
  end

  it "pins the marker and replay palette tokens with colour on" do
    text = render([invoice, cart], with_timeouts: true, color: :always)
    expect(text).to include("\e[33mTimeouts (2):\e[0m\n")
    expect(text).to include("\e[1m1. cart.rb:3\e[0m Cart#total \e[33m[timeout]\e[0m\n")
    expect(text).to include("  replay this timeout: \e[36msaboteur run --id 76a4a25dd1f208ee --seed 1\e[0m\n")
    expect(text).to include("\e[1m2. invoice.rb:3\e[0m Invoice#recalculate \e[33m[timeout]\e[0m\n")
  end

  it "prints neither blocks nor the tally when nothing timed out" do
    text = render([result_for(:killed)], with_timeouts: true)
    expect(text).not_to include("[timeout]")
    expect(text).not_to include("Timeouts (")
  end

  it "keeps the 9a tally as the default when the flag is off" do
    text = render([invoice], with_timeouts: false)
    expect(text).to include("Timeouts (1):\n  invoice.rb:3 Invoice#recalculate")
    expect(text).not_to include("[timeout]")
  end

  it "leaves the score and the canonical line byte-identical with and without the flag" do
    on = render([invoice, cart], with_timeouts: true)
    off = render([invoice, cart], with_timeouts: false)
    %w[Score: saboteur:].each do |prefix|
      expect(on.lines.grep(/^#{prefix}/)).to eq(off.lines.grep(/^#{prefix}/))
    end
    expect(on).to include("saboteur: 2 timeouts in 1s - score 100.0%")
  end

  it "renders a timeout and a survivor through the same renderer, marker and replay aside" do
    palette = Saboteur::Reporter::Palette.new(enabled: false)
    list = Saboteur::Reporter::SurvivorList.new(out, palette)
    root = File.dirname(cart.subject.file)

    timeout_report = Saboteur::Report.new(results: [cart], subjects: [cart.subject], wall_time: 1.0, root:,
                                          warnings: [], seed: 1)
    list.timeouts(timeout_report)
    timeout_text = out.string.dup

    survivor = timeout_result("class Cart\n  def total\n    @items.sum.round(2)\n  end\nend\n",
                              name: "cart.rb", from: ".round(2)", to: "", operator: "operand_replacement",
                              reason: nil, status: :survived)
    out.truncate(0)
    out.rewind
    survivor_report = Saboteur::Report.new(results: [survivor], subjects: [survivor.subject], wall_time: 1.0,
                                           root:, warnings: [], seed: 1)
    list.call(survivor_report, [survivor])
    survivor_text = out.string

    expect(timeout_text.lines - survivor_text.lines)
      .to eq(["Timeouts (1):\n",
              "1. cart.rb:3 Cart#total [timeout]\n",
              "  replay this timeout: saboteur run --id 76a4a25dd1f208ee --seed 1\n"])
    expect(survivor_text.lines - timeout_text.lines)
      .to eq(["Survivors (1) - changes your tests did not catch\n",
              "1. cart.rb:3 Cart#total [#1 of 1]\n"])
  end
end
