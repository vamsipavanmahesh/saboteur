# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Subject do
  let(:source) { "class A\n  def m(x)\n    x >= 1\n  end\nend\n" }
  let(:subject_under_test) { subjects_in(source).first }

  def edit(start_byte, end_byte, replacement, file: subject_under_test.file)
    Saboteur::MutationSource::Edit.new(file:, start_byte:, end_byte:, replacement:)
  end

  it "applies byte-range edits to the method text only" do
    at = source.index(">=")
    expect(subject_under_test.apply([edit(at, at + 2, ">")])).to eq("def m(x)\n    x > 1\n  end")
  end

  it "applies several non-overlapping edits regardless of order" do
    op = source.index(">=")
    one = source.index("1\n")
    text = subject_under_test.apply([edit(op, op + 2, "<"), edit(one, one + 1, "2")])
    expect(text).to eq("def m(x)\n    x < 2\n  end")
  end

  it "rejects edits outside the method" do
    expect { subject_under_test.apply([edit(0, 5, "module")]) }.to raise_error(ArgumentError, /outside/)
  end

  it "rejects overlapping edits" do
    at = source.index(">=")
    expect { subject_under_test.apply([edit(at, at + 2, ">"), edit(at + 1, at + 3, "x")]) }
      .to raise_error(ArgumentError, /overlapping/)
  end

  it "rejects edits for another file" do
    at = source.index(">=")
    expect { subject_under_test.apply([edit(at, at + 2, ">", file: "/elsewhere.rb")]) }
      .to raise_error(ArgumentError, /applied to subject/)
  end

  it "maps body lines (not the def line) for multi-line methods" do
    expect(subject_under_test.coverage_lines).to eq([3, 4])
  end

  it "maps the def line for one-line methods" do
    expect(subjects_in("class A\n  def m; 1; end\nend\n").first.coverage_lines).to eq([2])
  end

  it "returns the text around the def on its first and last lines" do
    expect(subject_under_test.surrounding_text).to eq(["  ", ""])
  end
end
