# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::TimeoutList, "the Timeouts findings section" do
  after { FileUtils.rm_rf(@dirs.to_a) }

  let(:out) { StringIO.new }

  def dir
    @dirs ||= []
    @dirs << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-pins-")))
    @dir
  end

  def timeout_result(source, name:, from:, to:, operator:, reason: "exceeded 2.0 s")
    path = File.join(dir, name)
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index(from, subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.size,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :timeout,
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

  it "prints no section and leaves no blank line behind when nothing timed out" do
    text = render([result_for(:killed)])
    expect(text).not_to include("Timeouts")
    expect(text).not_to start_with("\n")
  end

  it "prints the golden section, monochrome, ordered by file path then line" do
    expect(render([invoice, cart])).to include(<<~TEXT)
      Timeouts (2):
        cart.rb:3 Cart#total (operand_replacement, deadline 2s)
        invoice.rb:3 Invoice#recalculate (literal_number, deadline 2s)
    TEXT
  end

  it "prints the golden section with colour tokens at --color=always" do
    text = render([invoice, cart], color: :always)
    expect(text).to include("\e[33mTimeouts (2):\e[0m\n  " \
                            "cart.rb:3 Cart#total \e[2m(operand_replacement, deadline 2s)\e[0m\n  " \
                            "invoice.rb:3 Invoice#recalculate \e[2m(literal_number, deadline 2s)\e[0m\n")
  end

  it "sits after the last survivor block and before the canonical summary line" do
    text = render([result_for(:survived, covered_by: ["./spec/p_spec.rb[1:1]"]), invoice, cart])
    section = text.index("Timeouts (2):")
    expect(section).to be > text.index("+   2 def adult?; @age > 18; end")
    expect(section).to be < text.index("\nsaboteur: ")
  end

  it "counts one timeout in the singular" do
    # No survivors, so the section opens the output: no blank line before it.
    expect(render([invoice])).to start_with("Timeouts (1):\n")
  end

  it "prints the run's computed deadline, never a hardcoded one" do
    slow = timeout_result("class Slow\n  def call\n    @x = 1 + 2\n  end\nend\n",
                          name: "slow.rb", from: "+", to: "-", operator: "arithmetic", reason: "exceeded 6.52 s")
    expect(render([slow])).to include("(arithmetic, deadline 6.52s)")
  end

  it "names the operator alone when the timeout reason carries no deadline" do
    quiet = timeout_result("class Quiet\n  def call\n    @x = 1 + 2\n  end\nend\n",
                           name: "quiet.rb", from: "+", to: "-", operator: "arithmetic", reason: nil)
    expect(render([quiet])).to include("(arithmetic)\n")
  end

  it "keeps timeouts in the killed numerator of the score and the canonical line" do
    text = render([result_for(:killed, runtime: 0.5, killed_by: ["./spec/p_spec.rb[1:1]"]),
                   result_for(:survived, covered_by: ["./spec/p_spec.rb[1:1]"]), invoice])
    expect(text).to include("Score: 66.7% (2/3 killed, tested subjects)")
    expect(text).to include("\nsaboteur: 1 killed, 1 survived, 1 timeout in 1s - score 66.7%\n")
  end

  it "falls back to the operator-only form when the deadline capture is malformed" do
    odd = timeout_result("class Cart\n  def total\n    @items.sum.round(2)\n  end\nend\n",
                         name: "cart.rb", from: ".round(2)", to: "", operator: "operand_replacement",
                         reason: "exceeded 2.0.1 s")
    expect(render([odd])).to include("Timeouts (1):\n  cart.rb:3 Cart#total (operand_replacement)\n")
  end
end
