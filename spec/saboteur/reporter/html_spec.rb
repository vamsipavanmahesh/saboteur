# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Reporter::Html do
  let(:report) do
    test_id = "./spec/person_spec.rb[1:1]"
    report_of(result_for(:killed, killed_by: [test_id], covered_by: [test_id]),
              result_for(:survived, replacement: "=="),
              result_for(:skipped, replacement: "!=", reason: "no coverage"),
              warnings: ["Person#adult?: omitted 3 mutant(s) above max_mutants_per_method (2)"])
  end
  let(:html) { described_class.build(report) }

  it "is one self-contained page with no external resources" do
    expect(html).to start_with("<!DOCTYPE html>")
    expect(html).not_to match(%r{(?:src|href)\s*=\s*["']?(?:https?:)?//}i)
    expect(html).not_to include("<script")
  end

  it "shows the score, the seed and a count for every status" do
    expect(html).to include("Covered mutation score: 50.0%", "seed 1")
    %w[Killed Survived NoCoverage].each { |status| expect(html).to include(status) }
  end

  it "names the passing tests that covered a survivor, top 5" do
    tests = (1..6).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    page = described_class.build(report_of(result_for(:survived, covered_by: tests)))
    expect(page).to include("covered by 6 tests that passed: ./spec/person_spec.rb[1:1]", "(+1 more)")
    expect(page).not_to include("person_spec.rb[1:6],")
  end

  it "says a reused survivor's tests passed in an earlier run" do
    page = described_class.build(report_of(result_for(:survived, reused: true,
                                                                 covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(page).to include("covered by 1 test that passed in an earlier run: ./spec/person_spec.rb[1:1]")
  end

  it "separates the passing-test note from other notes with a semicolon" do
    survivor = result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])
    survivor.ignored = "equivalent"
    page = described_class.build(report_of(survivor))
    expect(page).to include("ignored: equivalent; covered by 1 test that passed: ./spec/person_spec.rb[1:1]")
  end

  it "joins the passing tests with a comma and a space" do
    tests = ["./spec/person_spec.rb[1:1]", "./spec/person_spec.rb[1:2]"]
    page = described_class.build(report_of(result_for(:survived, covered_by: tests)))
    expect(page).to include("covered by 2 tests that passed: ./spec/person_spec.rb[1:1], ./spec/person_spec.rb[1:2]<")
  end

  it "adds no passing-test note to a survivor with no covering tests" do
    page = described_class.build(report_of(result_for(:survived)))
    expect(page).not_to include("covered by")
  end

  it "shows exactly five covering tests with no 'more' note, and six with '+1 more'" do
    five = (1..5).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    exact = described_class.build(report_of(result_for(:survived, covered_by: five)))
    expect(exact).to include("covered by 5 tests that passed", "[1:5]")
    expect(exact).not_to include("more)")
    six = described_class.build(report_of(result_for(:survived, covered_by: five + ["./spec/person_spec.rb[1:6]"])))
    expect(six).to include("covered by 6 tests that passed", "[1:5] (+1 more)")
  end

  it "says test for one covering test and tests for two" do
    one = described_class.build(report_of(result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(one).to include("covered by 1 test that passed")
  end

  it "does not call a killed mutant's covering tests passing" do
    page = described_class.build(report_of(result_for(:killed, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(page).not_to include("that passed")
  end

  it "says how much of the score came from assertions and how much from crashes" do
    page = described_class.build(report_of(result_for(:killed, kill_cause: "assertion"),
                                           result_for(:killed, replacement: "<", kill_cause: "TypeError")))
    expect(page).to include("50.0% assertion, 50.0% crash")
  end

  it "shows the score without whole-body mutants" do
    page = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "TypeError"),
                                           result_for(:survived, replacement: "<", kill_cause: nil),
                                           result_for(:killed, replacement: "<=", kill_cause: "assertion")))
    expect(page).to include("Without whole-body mutants (body_nil, body_true, body_false, body_raise): 50.0%")
  end

  it "names timeouts and kills with no recorded cause, so the parts add up" do
    page = described_class.build(report_of(result_for(:killed, kill_cause: "assertion"),
                                           result_for(:timeout, replacement: "<"),
                                           result_for(:killed, replacement: "<=")))
    expect(page).to include("33.3% assertion, 0.0% crash, 33.3% timeout, 33.3% cause not recorded")
  end

  it "shows the whole-body line even when no kill has a recorded cause" do
    page = described_class.build(report_of(result_for(:killed, coarse: true),
                                           result_for(:killed, replacement: "<")))
    expect(page).to include("Without whole-body mutants", "Whole-body mutants alone: 100.0% over 1")
    expect(page).not_to include("A crash shows")
  end

  it "shows the whole-body line for a run of timeouts only" do
    page = described_class.build(report_of(result_for(:timeout, coarse: true),
                                           result_for(:timeout, replacement: "<")))
    expect(page).to include("Without whole-body mutants", "100.0%")
  end

  it "puts the kill split and the whole-body line in separate paragraphs" do
    page = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "TypeError"),
                                           result_for(:killed, replacement: "<", kill_cause: "assertion")))
    expect(page).to match(%r{not that a test checked a value\.</p>\n<p>Without whole-body mutants})
  end

  it "shows no whole-body line when the run has only whole-body mutants" do
    page = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "assertion"),
                                           result_for(:survived, coarse: true, replacement: "==")))
    expect(page).not_to include("Without whole-body mutants")
  end

  it "shows no whole-body line when the run has only fine mutants" do
    page = described_class.build(report_of(result_for(:killed, kill_cause: "assertion"),
                                           result_for(:survived, replacement: "==")))
    expect(page).not_to include("Without whole-body mutants")
  end

  it "splits the fine score only when some fine kill has a recorded cause" do
    known = described_class.build(report_of(result_for(:killed, coarse: true),
                                            result_for(:killed, replacement: "<", kill_cause: "assertion")))
    unknown = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "TypeError"),
                                              result_for(:killed, replacement: "<")))
    expect(known).to include("100.0% (100.0% assertion, 0.0% crash) over 1 mutants")
    expect(unknown).to include("100.0% over 1 mutants")
    expect(unknown).not_to include("(100.0% assertion")
  end

  it "lists each mutant with its operator, replacement and location" do
    expect(html).to include("comparison", "&gt;", "==", "person.rb", "line 2")
  end

  it "opens files that have survivors and shows the tests that killed a mutant" do
    expect(html).to include("<details open>")
    expect(html).to include("./spec/person_spec.rb[1:1]")
  end

  it "prints warnings and skipped subjects" do
    skipped = report_with_skipped_subject
    page = described_class.build(skipped)
    expect(page).to include("Skipped subjects", "no coverage", "K#m")
    expect(html).to include("omitted 3 mutant(s) above max_mutants_per_method (2)")
  end

  it "escapes source code and text so the page cannot run injected markup" do
    hostile = report_of(result_for(:survived, replacement: "<img src=x onerror=alert(1)>"),
                        warnings: ["<b>careful</b>"])
    page = described_class.build(hostile)
    expect(page).not_to include("<img src=x", "<b>careful")
    expect(page).to include("&lt;img src=x", "&lt;b&gt;careful")
  end

  it "says so when nothing was tested" do
    expect(described_class.build(report_of)).to include("Covered mutation score: n/a")
  end

  it "labels the score as covered-only, with its formula and what it leaves out" do
    expect(html).to include("(killed + timeout) / (killed + survived + timeout)", "NoCoverage",
                            "stay in the denominator", "different score",
                            "only the subjects of this run")
  end

  it "has a viewport tag, table headings and wrapping that keeps replacement whitespace" do
    expect(html).to include('<meta name="viewport"', "<th>Location</th>", "<th>Id</th>", "white-space:pre-wrap")
  end

  it "shows the stable id, the column and the original text, so same-line mutants differ" do
    first = result_for(:survived, replacement: "==")
    second = result_for(:survived, replacement: "<")
    page = described_class.build(report_of(first, second))
    expect(page).to include("<code>#{first.digest}</code>", "<code>#{second.digest}</code>", "line 2, column 20",
                            "<pre>&gt;=</pre> becomes <pre>==</pre>")
    expect(first.digest).not_to eq(second.digest)
  end

  it "shows only the replacements for a mutant with several edits" do
    source = person_subject.file_source
    edits = [[source.index(">="), 2, "<"], [source.index("18"), 2, "19"]].map do |at, length, text|
      Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: at, end_byte: at + length,
                                         replacement: text)
    end
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator: "pair", edits:)
    multi = Saboteur::MutantResult.new(subject: person_subject, mutation:, status: :survived,
                                       mutated_source: person_subject.apply(edits))
    page = described_class.build(report_of(multi))
    expect(page).to include("<pre>&lt; | 19</pre>")
    expect(page).not_to include("becomes")
  end

  it "marks a survivor on the ignore list as accepted and counts it apart from survivors to fix" do
    accepted = result_for(:survived, replacement: "==")
    accepted.ignored = "equivalent"
    page = described_class.build(report_of(accepted, result_for(:survived, replacement: "<")))
    expect(page).to include("Accepted", "ignored: equivalent", "Survivors: 1 to fix, 1")
  end

  it "styles every triage badge class it renders, or the badge is invisible (#304)" do
    page = described_class.build(report_of(result_for(:killed)))
    expect(page).to include(".Accepted,.Triage_accepted_equivalent{", ".Triage_wont_fix{", ".Triage_todo{")
  end

  # The status badge sits in front of the triage badge: dropping either
  # interpolation must break this pin (#304 dogfood).
  it "pins the full status + triage badge row (#304 dogfood)" do
    legacy = result_for(:survived, replacement: "==")
    legacy.ignored = "equivalent"
    wont_fix = result_for(:survived, replacement: "<")
    wont_fix.ignored = "legacy"
    wont_fix.triage_state = "wont_fix"
    page = described_class.build(report_of(legacy, wont_fix))
    expect(page).to include(
      %(<span class="status Survived">Survived</span> <span class="status Accepted">Accepted</span>),
      %(<span class="status Survived">Survived</span> <span class="status Triage_wont_fix">Won’t fix</span>)
    )
  end

  it "badges a wont_fix triage separately from accepted_equivalent (#155)" do
    accepted = result_for(:survived, replacement: "==")
    accepted.ignored = "equivalent"
    accepted.triage_state = "accepted_equivalent"
    wont_fix = result_for(:survived, replacement: "<")
    wont_fix.ignored = "legacy"
    wont_fix.triage_state = "wont_fix"
    page = described_class.build(report_of(accepted, wont_fix, result_for(:killed)))
    expect(page).to include("status Triage_accepted_equivalent\">Accepted<",
                            "status Triage_wont_fix\">Won\u2019t fix<", "Survivors: 0 to fix, 2")
  end

  it "badges a todo triage while the survivor still counts as one to fix (#155)" do
    todo = result_for(:survived, replacement: "==")
    todo.triage_state = "todo"
    todo.triage_reason = "fix in the next sprint"
    page = described_class.build(report_of(todo, result_for(:killed)))
    expect(page).to include('status Triage_todo">Todo<', "todo: fix in the next sprint", "Survivors: 1 to fix")
  end

  it "leaves NoCoverage out of the score but keeps accepted survivors in it" do
    ignored = result_for(:survived, replacement: "==")
    ignored.ignored = "equivalent"
    page = described_class.build(report_of(result_for(:killed), ignored, result_for(:skipped, reason: "no coverage")))
    expect(page).to include("Covered mutation score: 50.0%")
  end

  it "renders every status, and a report with no files" do
    all = report_of(result_for(:killed), result_for(:survived, replacement: "=="),
                    result_for(:timeout, replacement: "<"), result_for(:error, replacement: "<=", reason: "boom"),
                    result_for(:skipped, replacement: "!=", reason: "baseline failure"))
    expect(described_class.build(all)).to include("Timeout", "RuntimeError", "Ignored")
    expect(described_class.build(Saboteur::Report.new(results: [], subjects: [], wall_time: 0, root: "/"))).to include(
      "<h2>Files</h2>", "n/a"
    )
  end

  it "escapes hostile text in the file name, test name, status reason and skip reason" do
    hostile = "<script>alert(1)</script>"
    report = report_with_skipped_subject(reason: hostile)
    results = [result_for(:error, reason: hostile, killed_by: ["./spec/#{hostile}_spec.rb[1:1]"],
                                  covered_by: ["./spec/#{hostile}_spec.rb[1:1]"])]
    page = described_class.build(report_of(*results)) + described_class.build(report)
    expect(page).not_to include("<script>alert")
    expect(page).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
  end

  it "labels each status in a coloured badge, and a survivor is not described as killed" do
    page = described_class.build(report_of(result_for(:killed, killed_by: ["t"], covered_by: ["t"]),
                                           result_for(:survived, replacement: "==")))
    expect(page).to include('<span class="status Killed">Killed</span>',
                            '<span class="status Survived">Survived</span>')
    expect(page.scan("killed by").size).to eq(1)
    expect(page).not_to include('status Accepted">')
  end

  it "badges a survivor with its classification label (#192)" do
    page = described_class.build(report_of(result_for(:survived, covered_by: %w[t1])))
    badge_with_label = '<span class="status Survived">Survived</span> ' \
                       '<span class="classification">missing_test</span>'
    expect(page).to include(badge_with_label)
    page = described_class.build(report_of(result_for(:killed, covered_by: %w[t1])))
    expect(page).not_to include('<span class="classification">')
  end

  it "keeps the triage badge next to the classification label on an ignored survivor" do
    accepted = result_for(:survived, covered_by: %w[t1])
    accepted.ignored = "equivalent"
    page = described_class.build(report_of(accepted))
    badges = '<span class="status Survived">Survived</span> <span class="status Accepted">Accepted</span> ' \
             '<span class="classification">missing_test</span>'
    expect(page).to include(badges)
  end

  it "marks an ignore-list survivor with an Accepted badge" do
    accepted = result_for(:survived, replacement: "==")
    accepted.ignored = "equivalent"
    expect(described_class.build(report_of(accepted))).to include('<span class="status Accepted">Accepted</span>')
  end

  it "leaves out the seed, the warnings and the skipped subjects when there are none" do
    page = described_class.build(Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject],
                                                      wall_time: 1, root: File.dirname(person_subject.file)))
    expect(page).not_to include("seed", "<h2>Warnings</h2>", "<h2>Skipped subjects</h2>")
  end

  it "opens only the files that have survivors" do
    expect(described_class.build(report_of(result_for(:killed)))).to include("<details><summary>")
    expect(described_class.build(report_of(result_for(:survived)))).to include("<details open><summary>")
  end

  it "lists mutants in source order, then by column" do
    source = person_subject.file_source
    at = ->(text) { source.index(text) }
    make = lambda do |text, replacement|
      edit = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: at.call(text),
                                                end_byte: at.call(text) + text.size, replacement:)
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator: "x", edits: [edit])
      Saboteur::MutantResult.new(subject: person_subject, mutation:, status: :survived,
                                 mutated_source: person_subject.apply(mutation.edits))
    end
    page = described_class.build(report_of(make.call("18", "19"), make.call("@age", "@other"),
                                           make.call("adult?", "adults?")))
    expect(page.scan(/column (\d+)/).flatten.map(&:to_i)).to eq(page.scan(/column (\d+)/).flatten.map(&:to_i).sort)
    expect(page.index("adults?")).to be < page.index("@other")
    expect(page.index("@other")).to be < page.index("19</pre>")
  end

  it "writes the page to the given path, creating folders" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "report.html")
      described_class.new(path).call(report)
      expect(File.read(path)).to eq(html)
    end
  end

  def report_with_skipped_subject(reason: "no coverage")
    subject_under_test = subjects_in("class K\n  def m\n    1\n  end\nend\n").first
    Saboteur::Report.new(results: [], subjects: [subject_under_test], wall_time: 0,
                         root: File.dirname(subject_under_test.file),
                         skipped_subjects: { subject_under_test => reason })
  end

  describe "diff mode" do
    def diff_report(results, changed, subject: person_subject)
      scope = Saboteur::Engine::DiffScope.new({ subject.file => Set.new(changed) })
      Saboteur::Report.new(results:, subjects: [subject], wall_time: 1.0,
                           root: File.dirname(subject.file), review: true, diff_scope: scope)
    end

    # The mutated statement spans two lines, so the mutant is reported at its
    # first line while the change sits one line below it.
    def multiline_result
      source = <<~RUBY
        class Person
          def describe
            format("%s years",
                   age)
          end
        end
      RUBY
      subject = subjects_in(source, name: "person.rb").first
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: source.index("format"),
                                                end_byte: source.index(")") + 1, replacement: "age.to_s")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "statement_nil",
                                                        edits: [edit])
      result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                          mutated_source: subject.apply(mutation.edits))
      [subject, result]
    end

    it "names the changed line a mutant touches, under the mutant's own location" do
      page = described_class.build(diff_report([result_for(:survived)], [2]))
      expect(page).to match(%r{<td class="fit">line 2, column \d+<br>changed line 2</td>})
    end

    it "names the changed line when the mutated statement starts above it" do
      subject, result = multiline_result
      page = described_class.build(diff_report([result], [4], subject:))
      expect(page).to match(%r{<td class="fit">line 3, column \d+<br>changed line 4</td>})
    end

    it "lists every changed line a statement-spanning mutant touches" do
      subject, result = multiline_result
      page = described_class.build(diff_report([result], [3, 4], subject:))
      expect(page).to include("changed lines 3, 4")
    end

    it "names the changed lines of killed mutants too" do
      page = described_class.build(diff_report([result_for(:killed)], [2]))
      expect(page).to include("changed line 2")
    end

    it "says nothing about changed lines outside diff mode" do
      expect(described_class.build(report_of(result_for(:survived)))).not_to include("changed line")
    end
  end

  it "wraps each row's status badge in its own cell" do
    expect(html).to include('<td><span class="status Killed">Killed</span></td>')
  end

  it "keeps the closing tags on their own last line" do
    expect(html.lines.last).to eq("</body></html>\n")
  end

  it "joins two files' sections with a newline" do
    Dir.mktmpdir do |dir|
      results = %w[a b].map do |name|
        source = "class #{name.capitalize}\n  def m\n    1 >= 0\n  end\nend\n"
        path = File.join(dir, "#{name}.rb")
        File.write(path, source)
        subject = Saboteur::SubjectFinder.new.call(path).subjects.first
        at = source.index(">=")
        edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                                  replacement: ">")
        mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                          edits: [edit])
        Saboteur::MutantResult.new(subject:, mutation:, status: :killed,
                                   mutated_source: subject.apply(mutation.edits))
      end
      report = Saboteur::Report.new(results:, subjects: results.map(&:subject), wall_time: 1.0, root: dir,
                                    seed: 1, operator_policy: Saboteur::Config.new({}).operator_policy)
      expect(described_class.build(report)).to include("</details>\n<details")
    end
  end
end
