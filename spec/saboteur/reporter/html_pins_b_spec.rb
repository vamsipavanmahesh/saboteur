# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Pins the HTML reporter's score paragraphs, warnings, skipped subjects, file
# table and mutant rows against mutation survivors.
RSpec.describe Saboteur::Reporter::Html do
  let(:kept) { subjects_in("class K\n  def m(a)\n    a + 1 - 2\n  end\nend\n", name: "k.rb").first }
  let(:root) { File.dirname(kept.file) }

  def mutant(text, replacement, status = :survived, nth: 0, coarse: false, **)
    at = (0...kept.file_source.size).select { |i| kept.file_source[i, text.size] == text }.fetch(nth)
    edit = Saboteur::MutationSource::Edit.new(file: kept.file, start_byte: at, end_byte: at + text.size, replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: kept.id, operator: "op", edits: [edit], coarse:)
    Saboteur::MutantResult.new(subject: kept, mutation:, status:, mutated_source: kept.apply(mutation.edits), **)
  end

  def page_of(*results, **)
    described_class.build(Saboteur::Report.new(results:, subjects: [kept], wall_time: 1, root:, seed: 1,
                                               operator_policy: Saboteur::Config.new({}).operator_policy, **))
  end

  describe "the score split paragraphs" do
    let(:page) do
      page_of(mutant("+", "-", :killed, coarse: true, kill_cause: "TypeError"),
              mutant("1", "3", :killed, kill_cause: "assertion"), mutant("2", "5"))
    end

    it "prints the kill split and the whole-body line as two exact paragraphs" do
      expect(page).to include(<<~HTML.chomp)
        <p>Of the tested mutants: 33.3% assertion, 33.3% crash. A crash shows the code ran and broke, not that a test checked a value.</p>
        <p>Without whole-body mutants (body_nil, body_true, body_false, body_raise): 50.0% (50.0% assertion, 0.0% crash) over 2 mutants. Whole-body mutants alone: 100.0% over 1.</p>
        <p class="note">Wide tables scroll sideways.</p>
      HTML
    end
  end

  describe "warnings and skipped subjects" do
    it "prints each warning in its own escaped div under one heading" do
      page = page_of(mutant("1", "3"), warnings: ["w<1>", "w2"])
      expect(page).to include("<h2>Warnings</h2>\n<div class=\"warning\">w&lt;1&gt;</div>\n" \
                              "<div class=\"warning\">w2</div>")
    end

    it "prints a skipped-subject table with escaped subject, location and reason, one row each" do
      other = subjects_in("class Z\n  def q\n    1\n  end\nend\n", name: "z.rb").first
      page = page_of(mutant("1", "3"), skipped_subjects: { kept => "too <slow>", other => "no tests" })
      expect(page).to include(
        "<h2>Skipped subjects</h2>\n<div class=\"scroll\"><table><thead><tr><th>Subject</th><th>Location</th>" \
        "<th>Reason</th></tr></thead><tr><td>K#m</td><td>k.rb:2</td><td>too &lt;slow&gt;</td></tr>" \
        "<tr><td>Z#q</td><td>#{other.file}:2</td><td>no tests</td></tr></table></div>"
      )
    end
  end

  describe "the file table" do
    let(:results) do
      [mutant("2", "5"), mutant("a", "b", nth: 2), mutant("a", "c", nth: 1), mutant("1", "3"), mutant("1", "4")]
    end

    it "is closed when nothing survived and shows the file name and the mutant count" do
      page = page_of(mutant("1", "3", :killed))
      expect(page).to include("<details class=\"file\"><summary>k.rb (1 mutants)</summary>\n" \
                              "<div class=\"scroll\"><table><thead><tr>" \
                              "<th>Location</th><th>Status</th><th>Operator</th><th>Change</th><th>Id</th>" \
                              "<th>Notes</th></tr></thead>\n<tr>")
    end

    it "orders rows by line, then column, then id, and puts one newline between rows" do
      rows = page_of(*results).scan(%r{<tr><td class="fit">line (\d+), column (\d+)</td>.*?<code>(\h+)</code>})
      expect(rows.map { |line, col, _| [line.to_i, col.to_i] }).to eq([[2, 9], [3, 5], [3, 9], [3, 9], [3, 13]])
      same = rows.select { |line, col, _| line == "3" && col == "9" }.map(&:last)
      expect(same).to eq(same.sort)
      page = page_of(*results)
      expect(page).to include("</td></tr>\n<tr><td class=\"fit\">")
      expect(page).to include("</tr></table></div></details>")
    end
  end

  describe "inline suppressions" do
    let(:entries) do
      [{ file: File.join(root, "lib/a.rb"), line: 4, subject: "A#<m>", operator: "comparison", digest: "ab" * 8,
         reason: "covered <elsewhere>" },
       { file: "/outside/b.rb", line: 9, subject: "B#n", operator: "literal", digest: "cd" * 8, reason: "seen" }]
    end

    it "lists each one with its root-relative path, line, subject, operator, digest and reason, escaped" do
      page = page_of(mutant("1", "3"), inline_suppressions: entries)
      expect(page).to include(
        "<h2>Inline suppressions (2, outside the score)</h2><ul>" \
        "<li>lib/a.rb:4 A#&lt;m&gt; comparison <code>#{'ab' * 8}</code>: covered &lt;elsewhere&gt;</li>" \
        "<li>/outside/b.rb:9 B#n literal <code>#{'cd' * 8}</code>: seen</li></ul>"
      )
    end

    it "adds nothing when there are none" do
      expect(page_of(mutant("1", "3"))).not_to include("Inline suppressions")
    end
  end

  describe "a mutant row" do
    let(:ids) { %w[./a_spec.rb[1:1] ./b_spec.rb[1:1]] }
    let(:kills) { mutant("1", "3", :killed, killed_by: ids, covered_by: ids) }

    it "shows its location, operator and mutant id" do
      page = page_of(kills)
      expect(page).to include("<td class=\"fit\">line 3, column 9</td>", "<td>op</td>",
                              "<td class=\"fit\"><code>#{kills.digest}</code></td>")
    end

    it "shows its status badge in the status cell" do
      expect(page_of(kills)).to include("</td><td><span class=\"status Killed\">Killed</span></td><td>op</td>")
    end

    it "names the killing tests with a comma and a space" do
      expect(page_of(kills)).to include("killed by ./a_spec.rb[1:1], ./b_spec.rb[1:1]</td>")
    end

    it "shows no tests note for a mutant killed by none" do
      expect(page_of(mutant("1", "3", :killed))).to include("<td class=\"wide\"></td></tr>")
    end
  end

  describe "the change column" do
    it "shows the original and the replacement of a single edit, escaped" do
      expect(page_of(mutant("+", "<b>"))).to include("<pre>+</pre> becomes <pre>&lt;b&gt;</pre></td><td class=\"fit\">")
    end

    it "decodes a binary source as UTF-8 and replaces a split character" do
      text = "caf\u00e9#{' ' * 40}".b
      allow(kept).to receive(:file_source).and_return(text)
      edit = Saboteur::MutationSource::Edit.new(file: kept.file, start_byte: 0, end_byte: 4, replacement: "x")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: kept.id, operator: "op", edits: [edit])
      result = Saboteur::MutantResult.new(subject: kept, mutation:, status: :killed, mutated_source: "x")
      expect(page_of(result)).to include("<pre>caf\uFFFD</pre> becomes <pre>x</pre>")
    end
  end
end
