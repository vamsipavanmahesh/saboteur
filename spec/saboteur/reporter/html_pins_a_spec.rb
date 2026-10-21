# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::Html, "page pins" do
  let(:page) do
    described_class.build(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:survived, replacement: "==")))
  end

  it "opens the page with the head, title and heading" do
    expect(page).to include("<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">\n",
                            "<title>saboteur report</title>\n<style>", "</style>\n<script>",
                            "</script></head><body>\n",
                            "<h1>saboteur report</h1>\n<p><strong>Covered mutation score: 50.0%</strong> " \
                            "(1/2 killed, tested subjects)</p>\n")
    expect(page).to end_with("</table></div></details>\n</body></html>\n")
  end

  it "prints the subject, mutant and time counts on one exact line" do
    expect(page).to include("</strong>\n(1 subject, 2 mutants, 1.2s, seed 1)</p>\n")
  end

  it "explains the score and its limits" do
    expect(page).to include("<p class=\"note\">Covered mutation score = (killed + timeout) / (killed + survived + " \
                            "timeout). NoCoverage, errors, resource limits and skipped\nmutants are not counted. ")
    expect(page).to include("Stryker JSON may show a different score, because the schema counts NoCoverage as " \
                            "undetected.</p>\n")
  end

  it "puts the score split, the scroll note, the status counts and the survivor line in order" do
    expect(page).to include(
      "<p>Of the tested mutants: 50.0% assertion, 0.0% crash. A crash shows the code ran and broke, " \
      "not that a test checked a value.</p>\n<p class=\"note\">Wide tables scroll sideways.</p>\n",
      "<p><span class=\"status Killed\">Killed</span> 1 <span class=\"status Survived\">Survived</span> 1</p>\n",
      "<p>Survivors: 1 to fix, 0\naccepted on the ignore list (still shown as Survived, with the reason).</p>\n"
    )
  end

  it "leaves a blank line, not a stray split line, when nothing is split" do
    plain = described_class.build(report_of(result_for(:killed)))
    expect(plain).to include("undetected.</p>\n\n<p class=\"note\">Wide tables scroll sideways.</p>\n")
  end

  it "adds the whole-body line after the split line, separated by one newline" do
    whole = result_for(:killed, coarse: true, kill_cause: "assertion")
    fine = result_for(:killed, replacement: "<", kill_cause: "assertion")
    text = described_class.build(report_of(whole, fine))
    expect(text).to match(%r{crash\. A crash shows[^\n]*</p>\n<p>[^\n]*whole-body})
  end

  it "puts the Files section after the score details" do
    expect(page).to include("with the reason).</p>\n\n</details>\n\n<h2>Files</h2>\n")
    expect(page).to include("triage reasons.</p>\n<details class=\"file\" open>")
  end

  it "prints no inline suppression section when there are none" do
    expect(page).not_to include("Inline suppressions")
  end

  it "lists inline suppressions after the summary, with the exact heading" do
    root = File.dirname(person_subject.file)
    entry = { file: File.join(root, "lib/a.rb"), line: 4, subject: "A#b", operator: "comparison",
              digest: "abcd1234abcd1234", reason: "equivalent" }
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.25,
                                  root: root, seed: 1, inline_suppressions: [entry])
    text = described_class.build(report)
    expect(text).to include("<h2>Inline suppressions (1, outside the score)</h2><ul>" \
                            "<li>lib/a.rb:4 A#b comparison <code>abcd1234abcd1234</code>: equivalent</li></ul>")
    expect(text.index("Inline suppressions")).to be > text.index("accepted on the ignore list")
  end

  def second_subject_result
    other = subjects_in("class K\n  def m\n    1 < 2\n  end\nend\n").first
    at = other.file_source.index("<")
    edit = Saboteur::MutationSource::Edit.new(file: other.file, start_byte: at, end_byte: at + 1, replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: other.id, operator: "x", edits: [edit])
    [other, Saboteur::MutantResult.new(subject: other, mutation:, status: :killed,
                                       mutated_source: other.apply(mutation.edits))]
  end

  it "separates two file sections with one newline" do
    other, extra = second_subject_result
    report = Saboteur::Report.new(results: [result_for(:killed), extra], subjects: [person_subject, other],
                                  wall_time: 1.25, root: File.dirname(person_subject.file), seed: 1)
    text = described_class.build(report)
    expect(text.scan("</table></div></details>\n<details").size).to eq(1)
  end

  it "prints warnings then skipped subjects right after the summary, in that order" do
    other, = second_subject_result
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject, other], wall_time: 1.25,
                                  root: File.dirname(person_subject.file), seed: 1, warnings: ["careful"],
                                  skipped_subjects: { other => "no coverage" })
    text = described_class.build(report)
    expect(text).to include("</details>\n<h2>Warnings</h2>\n<div class=\"warning\">careful</div>" \
                            "<h2>Skipped subjects</h2>\n<div class=\"scroll\">")
    expect(text.index("Skipped subjects")).to be < text.index("<h2>Files</h2>")
  end
end
