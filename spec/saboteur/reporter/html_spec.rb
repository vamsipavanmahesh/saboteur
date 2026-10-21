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
    expect(html).not_to match(/<script[^>]*\ssrc\s*=/i)
    expect(html).not_to match(/<link\b/i)
    expect(html).not_to match(%r{<(img|iframe|audio|video|source)[^>]*\ssrc\s*=\s*["']?(?:https?:)?//}i)
    # The viewer UI carries one navigational link, to its own docs at
    # https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics
    # Nothing loads from the network; the page works from file://.
  end

  it "embeds the vendored viewer bundle inline, byte for byte" do
    bundle = File.binread(File.expand_path("../../../lib/saboteur/reporter/assets/mutation_report.js", __dir__))
    expect(html.b).to include(bundle)
  end

  it "embeds the report JSON for the viewer, parseable back out identically" do
    embedded = html[%r{<script type="application/json" id="saboteur-report-json">(.*?)</script>}m, 1]
    expect(embedded).not_to be_nil
    round_tripped = JSON.parse(embedded)
    expected = JSON.parse(JSON.generate(Saboteur::Reporter::Stryker.build(report)))
    expect(round_tripped).to eq(expected)
  end

  it "protects the JSON tag from a source string holding </script>" do
    mutation = comparison_mutation(replacement: "x = '</script>'")
    result = Saboteur::MutantResult.new(subject: person_subject, mutation:, status: :survived,
                                        mutated_source: person_subject.apply(mutation.edits))
    page = described_class.build(report_of(result))
    expect(page).to include('\u003c/script>')
    expect(page).not_to include("x = '</script>'")
    expect(page.scan(%r{</script}i).size).to eq(page.scan(/<script\b/i).size)
  end

  it "wraps the score explanation in a details section" do
    expect(html).to include("<details><summary>How the score is computed</summary>")
  end

  it "explains that the table repeats the viewer data with notes" do
    expect(html).to include("<p class=\"note\">The viewer above and this table list the same mutants; " \
                            "the table adds notes,\ncovering tests and triage reasons.</p>")
  end

  it "prints the table instead of the viewer: paper cannot scroll sideways" do
    style = html[%r{<style>(.*?)</style>}m, 1]
    expect(style).to include("@media print", "mutation-test-report-app{display:none}",
                             ".scroll{overflow-x:visible}", "table{min-width:0}")
  end

  it "wires the embedded JSON into the viewer app element" do
    expect(html).to include('document.querySelector("mutation-test-report-app").report =')
    expect(html).to include('JSON.parse(document.getElementById("saboteur-report-json").textContent)')
  end

  it "shows the mutant id in a code cell on every row" do
    result = result_for(:killed)
    page = described_class.build(report_of(result))
    expect(page).to include("<code>#{result.digest}</code>")
  end

  it "renders the notes cell with its wrapper and the passing-tests note" do
    result = result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])
    page = described_class.build(report_of(result))
    expect(page).to include('<td class="wide">covered by 1 test that passed: ./spec/person_spec.rb[1:1]</td>')
  end

  it "puts no copy button on a killed-only report" do
    page = described_class.build(report_of(result_for(:killed)))
    expect(page.scan('class="copy"')).to be_empty
  end

  it "gives survivor rows a copy button for the replay command, killed rows none" do
    survivor = result_for(:survived)
    page = described_class.build(report_of(result_for(:killed), survivor))
    expect(page).to include(%(<button class="copy" data-copy="saboteur run --id #{survivor.digest} --seed 1" ))
    expect(page).to include("copy</button></td>")
    expect(page.scan('class="copy"').size).to eq(1)
    expect(page).to include('document.addEventListener("click"', "execCommand")
  end

  it "shows the viewer in dark mode by default" do
    expect(html).to include('<mutation-test-report-app theme="dark"')
  end

  it "keeps an accepted-equivalent survivor Survived with its ignored reason in the viewer data" do
    survivor = result_for(:survived)
    survivor.ignored = "equivalent"
    mutant = embedded_mutants(described_class.build(report_of(survivor))).first
    expect(mutant.values_at("status", "statusReason")).to eq(["Survived", "ignored: equivalent"])
  end

  it "marks an uncovered subject's mutants NoCoverage in the viewer data" do
    page = described_class.build(report_of(result_for(:skipped, reason: "no coverage")))
    expect(embedded_mutants(page).first["status"]).to eq("NoCoverage")
  end

  it "shows the honest pair: the tested-subject score and the not-scored count" do
    untested = subjects_in(ReportHelpers::PERSON, name: "untested.rb").first
    page = described_class.build(report_of(result_for(:killed), skipped_subjects: { untested => "no coverage" }))
    expect(page).to include("Covered mutation score: 100.0%</strong> (1/1 killed, tested subjects)")
    expect(page).to include("tested subjects) - 1 subject not scored - no tests exist")
  end

  it "omits the not-scored clause when every skipped subject has another reason" do
    untested = subjects_in(ReportHelpers::PERSON, name: "broken.rb").first
    page = described_class.build(report_of(result_for(:killed), skipped_subjects: { untested => "parse error" }))
    expect(page).not_to include("not scored")
  end

  it "shows no not-scored clause for a run without skipped subjects" do
    expect(html).not_to include("not scored")
  end

  it "shows no killed fraction for a run that tested nothing" do
    page = described_class.build(report_of)
    expect(page).to include("Covered mutation score: n/a")
    expect(page).not_to include("killed, tested subjects")
  end

  it "says subjects when more than one subject is not scored" do
    pair = subjects_in("#{ReportHelpers::PERSON}\n#{ReportHelpers::PERSON.sub('Person', 'PersonTwo')}",
                       name: "untested.rb")
    skipped = pair.to_h { |subject| [subject, "no coverage"] }
    page = described_class.build(report_of(result_for(:killed), skipped_subjects: skipped))
    expect(page).to include("2 subjects not scored - no tests exist")
  end

  def visible_html(page)
    page.gsub(%r{<script\b.*?</script>}m, "")
  end

  def embedded_mutants(page)
    embedded = page[%r{<script type="application/json" id="saboteur-report-json">(.*?)</script>}m, 1]
    JSON.parse(embedded).fetch("files").values.flat_map { |entry| entry.fetch("mutants") }
  end

  it "shows the score, the seed and a count for every status" do
    expect(html).to include("Covered mutation score: 50.0%", "seed 1")
    %w[Killed Survived NoCoverage].each { |status| expect(html).to include(status) }
  end

  it "names the passing tests that covered a survivor, top 5" do
    tests = (1..6).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    page = described_class.build(report_of(result_for(:survived, covered_by: tests)))
    expect(page).to include("covered by 6 tests that passed: ./spec/person_spec.rb[1:1]", "(+1 more)")
    expect(visible_html(page)).not_to include("person_spec.rb[1:6],")
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
    expect(visible_html(page)).not_to include("covered by")
  end

  it "shows exactly five covering tests with no 'more' note, and six with '+1 more'" do
    five = (1..5).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    exact = described_class.build(report_of(result_for(:survived, covered_by: five)))
    expect(exact).to include("covered by 5 tests that passed", "[1:5]")
    expect(visible_html(exact)).not_to include("more)")
    six = described_class.build(report_of(result_for(:survived, covered_by: five + ["./spec/person_spec.rb[1:6]"])))
    expect(six).to include("covered by 6 tests that passed", "[1:5] (+1 more)")
  end

  it "says test for one covering test and tests for two" do
    one = described_class.build(report_of(result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(one).to include("covered by 1 test that passed")
  end

  it "does not call a killed mutant's covering tests passing" do
    page = described_class.build(report_of(result_for(:killed, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(visible_html(page)).not_to include("that passed")
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
    expect(html).to include('<details class="file" open>')
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
    expect(visible_html(page).scan("killed by").size).to eq(1)
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

  describe "collapsing survivor files beyond the open budget" do
    def write_subject(dir, name)
      path = File.join(dir, name)
      File.write(path, ReportHelpers::PERSON)
      Saboteur::SubjectFinder.new.call(path).subjects.first
    end

    def result_on(subject, status, replacement)
      at = subject.file_source.index(">=")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                                replacement:)
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                        edits: [edit], coarse: false)
      Saboteur::MutantResult.new(subject:, mutation:, status:, mutated_source: subject.apply(mutation.edits))
    end

    def page_for(dir, results)
      report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root: dir,
                                    operator_policy: Saboteur::Config.new({}).operator_policy)
      described_class.build(report)
    end

    it "stops opening files once the open rows reach the budget, keeping the survivor count visible" do
      Dir.mktmpdir do |dir|
        a = write_subject(dir, "a.rb")
        b = write_subject(dir, "b.rb")
        results = [result_on(a, :survived, ">")] + (1..39).map { |i| result_on(a, :killed, "<#{i}") }
        results += [result_on(b, :survived, ">"), result_on(b, :killed, "<"), result_on(b, :killed, "!=")]
        page = page_for(dir, results)
        expect(page).to include('<details class="file" open><summary>a.rb (40 mutants)</summary>')
        expect(page).to include('<details class="file"><summary>b.rb (3 mutants, 1 survivor)</summary>')
        expect(page).to include(">1 file with survivors collapsed - ", ">expand all</a>")
        expect(page).to include("<a href=\"#files\" onclick=\"document.querySelectorAll('details.file')" \
                                ".forEach(function(d){d.open=true});return false\">expand all</a></p>\n")
      end
    end

    it "opens only the top survivor-bearing files, ranked by survivor count" do
      Dir.mktmpdir do |dir|
        results = (0..11).map { |i| result_on(write_subject(dir, format("f%02d.rb", i)), :survived, ">") }
        page = page_for(dir, results)
        expect(page).to include('<details class="file" open><summary>f00.rb (1 mutants)</summary>')
        expect(page).to include('<details class="file" open><summary>f09.rb (1 mutants)</summary>')
        expect(page).to include('<details class="file"><summary>f10.rb (1 mutants, 1 survivor)</summary>')
        expect(page).to include('<details class="file"><summary>f11.rb (1 mutants, 1 survivor)</summary>')
        expect(page).to include(">2 files with survivors collapsed - ")
      end
    end

    it "ranks by survivor count first, names plural survivors, and leaves survivor-free files out of the count" do
      Dir.mktmpdir do |dir|
        pair = lambda do |name|
          subject = write_subject(dir, name)
          [result_on(subject, :survived, ">"), result_on(subject, :survived, "<")]
        end
        one = write_subject(dir, "a_one.rb")
        quiet = write_subject(dir, "k_quiet.rb")
        results = [result_on(one, :survived, ">"), result_on(quiet, :killed, ">")]
        results += (0..9).flat_map { |i| pair.call(format("g%02d.rb", i)) } + pair.call("h.rb")
        page = page_for(dir, results)
        expect(page).to include('<details class="file" open><summary>g00.rb (2 mutants)</summary>')
        expect(page).to include('<details class="file"><summary>h.rb (2 mutants, 2 survivors)</summary>')
        expect(page).to include('<details class="file"><summary>a_one.rb (1 mutants, 1 survivor)</summary>')
        expect(page).to include(">2 files with survivors collapsed - ")
        expect(page).to include('<details class="file"><summary>k_quiet.rb (1 mutants)</summary>')
      end
    end

    it "ranks ties by file name, whatever order the files were added in" do
      Dir.mktmpdir do |dir|
        results = (0..10).reverse_each.map { |i| result_on(write_subject(dir, format("f%02d.rb", i)), :survived, ">") }
        page = page_for(dir, results)
        expect(page).to include('<details class="file" open><summary>f00.rb (1 mutants)</summary>')
        expect(page).to include('<details class="file"><summary>f10.rb (1 mutants, 1 survivor)</summary>')
      end
    end

    it "never opens or counts a file without survivors" do
      Dir.mktmpdir do |dir|
        a = write_subject(dir, "a.rb")
        quiet = write_subject(dir, "k.rb")
        page = page_for(dir, [result_on(a, :survived, ">"), result_on(quiet, :killed, ">")])
        expect(page).to include('<details class="file"><summary>k.rb (1 mutants)</summary>')
        expect(page).not_to include("collapsed")
      end
    end

    it "opens the next file while the open rows are under the budget and stops exactly at it" do
      Dir.mktmpdir do |dir|
        budget = Saboteur::Reporter::Html::OPEN_ROW_BUDGET
        [[budget - 1, true], [budget, false]].each do |rows, next_opens|
          a = write_subject(dir, "a#{rows}.rb")
          b = write_subject(dir, "b#{rows}.rb")
          results = [result_on(a, :survived, ">")] + (1...rows).map { |i| result_on(a, :killed, "<#{i}") }
          page = page_for(dir, results + [result_on(b, :survived, ">")])
          expect(page.include?(%(<details class="file" open><summary>b#{rows}.rb))).to eq(next_opens)
        end
      end
    end

    it "keeps every survivor file open and shows no control on a small run" do
      Dir.mktmpdir do |dir|
        a = write_subject(dir, "a.rb")
        b = write_subject(dir, "b.rb")
        page = page_for(dir, [result_on(a, :survived, ">"), result_on(b, :survived, ">")])
        expect(page.scan('<details class="file" open>').size).to eq(2)
        expect(page).not_to include("collapsed", "survivor)</summary>")
      end
    end
  end

  it "opens only the files that have survivors" do
    expect(described_class.build(report_of(result_for(:killed)))).to include("<details><summary>")
    expect(described_class.build(report_of(result_for(:survived)))).to include('<details class="file" open><summary>')
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
    expect(visible_html(page).index("adults?")).to be < visible_html(page).index("@other")
    expect(page.index("@other")).to be < page.index("19</pre>")
  end

  it "writes the page to the given path, creating folders" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "report.html")
      described_class.new(path).call(report)
      expect(File.binread(path)).to eq(html.b)
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
      # The location cell stays silent; the embedded JSON always describes the
      # survivor ranking ("nearer changed lines"), so pin the cell markup.
      expect(described_class.build(report_of(result_for(:survived)))).not_to match(/<br>changed lines?/i)
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
