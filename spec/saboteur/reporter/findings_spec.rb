# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

RSpec.describe Saboteur::Reporter::Findings do
  def build(report)
    JSON.parse(JSON.generate(described_class.build(report)))
  end

  def coarse_survivor(subject)
    at = subject.file_source.index("@age")
    finish = subject.file_source.index("18") + 2
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: finish,
                                              replacement: "nil")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "nil",
                                                      edits: [edit], coarse: true)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits))
  end

  # Writes the sources into one directory and returns [root, subjects], so
  # every path in the findings is relative to the same root.
  def project(sources)
    dir = File.realpath(Dir.mktmpdir("saboteur-findings-"))
    subjects = sources.map do |name, source|
      path = File.join(dir, name)
      File.write(path, source)
      Saboteur::SubjectFinder.new.call(path).subjects.first
    end
    [dir, subjects]
  end

  it "declares its version, the bound and the published ordering" do
    findings = build(report_of)
    expect(findings.values_at("version", "limit", "ordering")).to eq(
      [1, 10, "coarse survivors first, then file, line and digest"]
    )
  end

  it "is empty when nothing survived" do
    findings = build(report_of(result_for(:killed)))
    expect(findings).to include("survivors" => [], "survivorsTruncated" => 0,
                                "accepted" => [], "acceptedTruncated" => 0)
  end

  it "carries everything a file/line note needs for one survivor" do
    findings = build(report_of(result_for(:survived)))
    finding = only(findings.fetch("survivors"))
    expect(finding).to eq(
      "digest" => person_result_digest, "path" => "person.rb", "line" => 2, "endLine" => 2,
      "subject" => "Person#adult?", "operator" => "comparison", "original" => ">=",
      "replacement" => ">", "coarse" => false
    )
  end

  it "lists survivors accepted on the ignore list apart, with their reason" do
    survivor = result_for(:survived)
    survivor.ignored = "equivalent"
    findings = build(report_of(survivor))
    expect(findings.fetch("survivors")).to eq([])
    expect(only(findings.fetch("accepted")))
      .to include("operator" => "comparison", "reason" => "equivalent")
  end

  it "bounds the list and counts what it left out" do
    replacements = %w[> < == != <= >= + - * / %]
    findings = build(report_of(*replacements.map { |r| result_for(:survived, replacement: r) }))
    expect(findings.fetch("survivors").size).to eq(10)
    expect(findings.fetch("survivorsTruncated")).to eq(1)
  end

  it "orders coarse survivors first, then by file, line and digest" do
    root, (first, second) = project("b.rb" => ReportHelpers::PERSON, "a.rb" => ReportHelpers::PERSON)
    fine_b = survivor_for(first, replacement: "==")
    coarse_b = coarse_survivor(first)
    fine_a = survivor_for(second, replacement: "!=")
    coarse_a = coarse_survivor(second)
    report = Saboteur::Report.new(results: [fine_b, coarse_b, fine_a, coarse_a], subjects: [first, second],
                                  wall_time: 1.0, root:, seed: 1)
    findings = build(report)
    expect(findings.fetch("survivors").map { |f| [f["path"], f["coarse"]] })
      .to eq([["a.rb", true], ["b.rb", true], ["a.rb", false], ["b.rb", false]])
  end

  it "breaks a tie on one line by digest, so the order never wobbles" do
    one = result_for(:survived, replacement: "==")
    two = result_for(:survived, replacement: "!=")
    findings = build(report_of(two, one))
    digests = findings.fetch("survivors").map { |f| f.fetch("digest") }
    expect(digests).to eq([one.digest, two.digest].sort)
  end

  it "joins a multi-edit mutant's texts like the Stryker report does" do
    source = <<~RUBY
      class Pair
        def call
          alpha + beta
        end
      end
    RUBY
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    finish = subject.file_source.index("beta") + "beta".size
    edits = [
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 5,
                                         replacement: "gamma"),
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: finish - 4, end_byte: finish,
                                         replacement: "delta")
    ]
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "rename",
                                                      edits:)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root:, seed: 1)
    finding = only(build(report).fetch("survivors"))
    expect(finding.values_at("original", "replacement", "line", "endLine"))
      .to eq(["alpha | beta", "gamma | delta", 3, 3])
  end

  it "keeps an edit that ends on a line boundary on the line above" do
    source = "class Pair\n  def call\n    alpha + beta\n\n  end\nend\n"
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    finish = at + "alpha + beta\n\n".size
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: finish,
                                              replacement: "nil")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "nil", edits: [edit])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root:, seed: 1)
    expect(only(build(report).fetch("survivors")).fetch("endLine")).to eq(4)
  end

  it "survives invalid UTF-8 and frozen strings, which JSON cannot hold as is" do
    survivor = result_for(:survived, replacement: ">\xFF".b)
    frozen = result_for(:survived, replacement: +"<")
    findings = build(report_of(survivor, frozen))
    replacements = findings.fetch("survivors").map { |f| f.fetch("replacement") }
    expect(replacements).to contain_exactly(">�", "<")
  end

  def only(list)
    raise "expected exactly one finding, got #{list.size}" unless list.size == 1

    list.first
  end

  def survivor_for(subject, replacement:)
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                              replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                      edits: [edit])
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits))
  end

  def person_result_digest
    result_for(:survived).digest
  end
end
