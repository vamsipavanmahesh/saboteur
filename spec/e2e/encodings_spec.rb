# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks the byte-offset arithmetic (issue #117): edits land on the right
# characters when a file has CRLF line ends, a UTF-8 BOM, or multibyte text
# before the mutation point, and reported columns count characters.
RSpec.describe "encodings and offsets (end to end)", :e2e do
  let(:sources) do
    {
      "crlf.rb" => "# frozen_string_literal: true\r\n\r\nclass Crlf\r\n  def total(a, b)\r\n    a + b\r\n  " \
                   "end\r\nend\r\n",
      "bom.rb" => "\xEF\xBB\xBF# frozen_string_literal: true\n\nclass Bom\n  def total(a, b)\n    a + b\n  end\nend\n",
      "multibyte.rb" => "# frozen_string_literal: true\n\n# caf\u00e9 \u20ac \u{1F600}\nclass Multibyte\n  " \
                        "LABEL = \"\u00e9\u00e9\u00e9\"\n\n  def total(a, b) = \"\u00e9\u00e9\" + (a + b).to_s\nend\n"
    }
  end

  # [file, mutator, line, first column, last column]: columns count characters.
  let(:expected) do
    [
      ["lib/crlf.rb", "body_nil", 5, 5, 10], ["lib/crlf.rb", "body_raise", 5, 5, 10],
      ["lib/crlf.rb", "arithmetic", 5, 7, 8],
      ["lib/bom.rb", "body_nil", 5, 5, 10], ["lib/bom.rb", "body_raise", 5, 5, 10],
      ["lib/bom.rb", "arithmetic", 5, 7, 8],
      ["lib/multibyte.rb", "body_nil", 7, 21, 40], ["lib/multibyte.rb", "body_raise", 7, 21, 40],
      ["lib/multibyte.rb", "arithmetic", 7, 31, 32], ["lib/multibyte.rb", "literal_string", 7, 21, 25],
      # operand_replacement (#238) replaces each operand of both + calls;
      # columns still count characters across the multibyte text.
      ["lib/crlf.rb", "operand_replacement", 5, 5, 10], ["lib/crlf.rb", "operand_replacement", 5, 5, 10],
      ["lib/bom.rb", "operand_replacement", 5, 5, 10], ["lib/bom.rb", "operand_replacement", 5, 5, 10],
      ["lib/multibyte.rb", "operand_replacement", 7, 21, 40], ["lib/multibyte.rb", "operand_replacement", 7, 21, 40],
      ["lib/multibyte.rb", "operand_replacement", 7, 29, 34], ["lib/multibyte.rb", "operand_replacement", 7, 29, 34],
      # unary_insertion puts a - before each variable operand of the inner
      # a + b calls; the insertion column is the operand's first character.
      # The string-concatenation call in multibyte.rb emits none.
      ["lib/crlf.rb", "unary_insertion", 5, 5, 5], ["lib/crlf.rb", "unary_insertion", 5, 9, 9],
      ["lib/bom.rb", "unary_insertion", 5, 5, 5], ["lib/bom.rb", "unary_insertion", 5, 9, 9],
      ["lib/multibyte.rb", "unary_insertion", 7, 29, 29], ["lib/multibyte.rb", "unary_insertion", 7, 33, 33]
    ]
  end

  def encodings_project
    dir = copy_fixture("encodings")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    sources.each { |name, bytes| File.binwrite(File.join(dir, "lib", name), bytes.b) }
    dir
  end

  it "mutates files with CRLF, a BOM and multibyte text at the right offsets, and kills every mutant" do
    run = saboteur(encodings_project)
    expect(run.status).to eq(0), other_outcomes(run)
    found = run.json.fetch("files").flat_map do |file, report|
      report.fetch("mutants").map do |m|
        loc = m.fetch("location")
        [file, m.fetch("mutatorName"), loc.dig("start", "line"), loc.dig("start", "column"), loc.dig("end", "column")]
      end
    end
    expect(found).to match_array(expected)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "leaves the CRLF and BOM bytes of the source untouched" do
    dir = encodings_project
    saboteur(dir)
    sources.each { |name, bytes| expect(File.binread(File.join(dir, "lib", name))).to eq(bytes.b) }
  end
end
