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

  it "labels findings with their classification, only when there is a signal (#192)" do
    findings = build(report_of(result_for(:survived, covered_by: %w[t1]),
                               result_for(:survived, replacement: "=="),
                               result_for(:survived, replacement: "<", coarse: true)))
    expect(findings["survivors"].map { |f| f["classification"] }).to contain_exactly("boundary", "input_gap", nil)
  end

  it "declares its version, the bound and the published ordering" do
    findings = build(report_of)
    expect(findings.values_at("version", "limit", "ordering")).to eq(
      [1, 10, Saboteur::Reporter::SurvivorRanking::ORDERING]
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
      "replacement" => ">", "edits" => [{ "line" => 2, "endLine" => 2, "original" => ">=",
                                          "replacement" => ">" }],
      "coarse" => false, "classification" => "input_gap"
    )
  end

  it "names the changed lines a survivor touches in diff mode, and omits the key otherwise" do
    scope = Saboteur::Engine::DiffScope.new({ person_subject.file => Set.new([2]) })
    review = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true, diff_scope: scope)
    expect(only(build(review).fetch("survivors"))).to include("changedLines" => [2])
    expect(only(build(report_of(result_for(:survived))).fetch("survivors"))).not_to have_key("changedLines")
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

  # #1150: full_order is live-ranked-then-accepted, concatenated - an
  # accepted survivor never jumps ahead of a live one, however it ranks.
  it "keeps accepted digests behind every live one in the order array" do
    live = result_for(:survived)
    accepted = result_for(:survived, replacement: "==")
    accepted.ignored = "equivalent"
    findings = build(report_of(live, accepted))
    expect(findings.fetch("order")).to eq([live.digest, accepted.digest])
  end

  it "carries every survivor digest in the terminal's ranked order, uncapped (#1150)" do
    replacements = %w[> < == != <= >= + - * / %]
    findings = build(report_of(*replacements.map { |r| result_for(:survived, replacement: r) }))
    order = findings.fetch("order")
    expect(order.size).to eq(11)
    expect(order.first(10)).to eq(findings.fetch("survivors").map { |f| f["digest"] })
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

  it "orders two survivors in one file by line, before the digest tie-break" do
    source = "class Pair\n  def call\n    alpha +\n      beta\n  end\nend\n"
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    beta_at = subject.file_source.index("beta")
    make = lambda do |start, finish, replacement|
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start, end_byte: finish,
                                                replacement:)
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "rename",
                                                        edits: [edit])
      Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                 mutated_source: subject.apply(mutation.edits))
    end
    earlier = make.call(at, at + 5, "gamma")
    later = make.call(beta_at, beta_at + 4, "delta")
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [later, earlier], subjects: [subject], wall_time: 1.0,
                                  root:, seed: 1)
    findings = build(report).fetch("survivors")
    expect(findings.map { |f| f["line"] }).to eq([3, 4])
    # The spec only pins the order when the line decides it.
    expect([earlier.digest, later.digest]).not_to eq([earlier.digest, later.digest].sort)
  end

  it "joins a multi-edit mutant's texts like the Stryker report does, with one location per edit" do
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
    expect(finding.fetch("edits")).to eq([
                                           { "line" => 3, "endLine" => 3, "original" => "alpha",
                                             "replacement" => "gamma" },
                                           { "line" => 3, "endLine" => 3, "original" => "beta",
                                             "replacement" => "delta" }
                                         ])
  end

  it "sorts a reversed multi-edit array into a sane range, like Subject#apply does" do
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
    # Handed over last edit first: a custom mutation source may not sort.
    edits = [
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: finish - 4, end_byte: finish,
                                         replacement: "delta"),
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 5,
                                         replacement: "gamma")
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
    expect(finding.fetch("edits").map { |e| e.fetch("original") }).to eq(%w[alpha beta])
  end

  it "bounds the accepted list and counts what it left out" do
    accepted = %w[> < == != <= >= + - * / %].map do |replacement|
      survivor = result_for(:survived, replacement:)
      survivor.ignored = "equivalent"
      survivor
    end
    findings = build(report_of(*accepted))
    expect(findings.fetch("accepted").size).to eq(10)
    expect(findings.fetch("acceptedTruncated")).to eq(1)
  end

  it "ranges a reversed multi-edit mutant across the lines its edits touch" do
    source = "class Pair\n  def call\n    alpha +\n      beta\n  end\nend\n"
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    beta_at = subject.file_source.index("beta")
    # Handed over last edit first, spanning two lines.
    edits = [
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: beta_at, end_byte: beta_at + 4,
                                         replacement: "delta"),
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 5,
                                         replacement: "gamma")
    ]
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "rename",
                                                      edits:)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root:, seed: 1)
    finding = only(build(report).fetch("survivors"))
    expect(finding.values_at("line", "endLine", "original", "replacement"))
      .to eq([3, 4, "alpha | beta", "gamma | delta"])
    expect(finding.fetch("edits").map { |e| [e["line"], e["original"]] })
      .to eq([[3, "alpha"], [4, "beta"]])
  end

  it "locates a zero-width insertion on its own line, with an empty original" do
    source = "class Pair\n  def call\n    alpha + beta\n  end\nend\n"
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at,
                                              replacement: "raise ")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "insertion",
                                                      edits: [edit])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root:, seed: 1)
    finding = only(build(report).fetch("survivors"))
    expect(finding.values_at("line", "endLine", "original", "replacement"))
      .to eq([3, 3, "", "raise "])
  end

  it "ranges a mixed mutant past a zero-width insertion that starts a later line" do
    source = "class Pair\n  def call\n    alpha + beta\n\n  end\nend\n"
    subject = project("pair.rb" => source).last.first
    at = subject.file_source.index("alpha")
    later = subject.file_source.index("  end")
    edits = [
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: later, end_byte: later,
                                         replacement: "raise; "),
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 5,
                                         replacement: "gamma")
    ]
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "mixed",
                                                      edits:)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    root = File.dirname(subject.file)
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root:, seed: 1)
    finding = only(build(report).fetch("survivors"))
    # The insertion sits at the start of line 5, so the range reaches line 5.
    expect(finding.values_at("line", "endLine")).to eq([3, 5])
    expect(finding.fetch("edits").map { |e| [e["line"], e["endLine"]] }).to eq([[3, 3], [5, 5]])
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
    finding = only(build(report).fetch("survivors"))
    expect(finding.fetch("endLine")).to eq(4)
    expect(finding.fetch("edits").map { |e| e.fetch("endLine") }).to eq([4])
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
