# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe Saboteur::Reporter::Stryker, "pins" do
  def payload_for(report)
    JSON.parse(JSON.generate(described_class.build(report)))
  end

  def mutants_of(report)
    payload_for(report).dig("files", "person.rb", "mutants")
  end

  it "names the project root" do
    report = report_of(result_for(:killed))
    expect(payload_for(report)["projectRoot"]).to eq(report.root)
  end

  it "lists a test that only killed a mutant under its test file" do
    killer = "./spec/k_spec.rb[1:1]"
    payload = payload_for(report_of(result_for(:killed, killed_by: [killer], covered_by: [])))
    expect(payload["testFiles"]).to eq("spec/k_spec.rb" => { "tests" => [{ "id" => "0", "name" => killer }] })
  end

  it "groups a test name that does not start with a spec path under the empty path" do
    expect(described_class.test_files("a\nb.rb[1]" => "0").keys).to eq([""])
  end

  it "marks every mutant as not static" do
    expect(mutants_of(report_of(result_for(:killed))).first).to include("static" => false)
  end

  it "leaves killedBy and coveredBy out when there are none" do
    mutant = mutants_of(report_of(result_for(:survived))).first
    expect(mutant).not_to have_key("killedBy")
    expect(mutant).not_to have_key("coveredBy")
  end

  it "rounds the duration to the nearest millisecond" do
    expect(mutants_of(report_of(result_for(:killed, runtime: 1.2346))).first["duration"]).to eql(1235)
    expect(mutants_of(report_of(result_for(:killed, runtime: 1.2344))).first["duration"]).to eql(1234)
  end

  it "reads a binary source as UTF-8 text" do
    source = "#{ReportHelpers::PERSON}# caf\u00e9\n".b
    allow(person_subject).to receive(:file_source).and_return(source)
    entry = described_class.file_entry([result_for(:killed)], {})
    expect(entry[:source]).to eq("#{ReportHelpers::PERSON}# caf\u00e9\n")
    expect(entry[:source].encoding).to eq(Encoding::UTF_8)
  end

  it "locates a mutant by its first edit" do
    subject = person_subject
    name = subject.file_source.index("adult?")
    first = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: name, end_byte: name + 6,
                                               replacement: "x")
    at = subject.file_source.index(">=")
    last = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                      edits: [first, last], coarse: false)
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                                        mutated_source: subject.apply([first, last]))
    expect(mutants_of(report_of(result)).first["location"]).to eq(
      "start" => { "line" => 2, "column" => 7 }, "end" => { "line" => 2, "column" => 13 }
    )
  end

  describe ".position" do
    it "counts columns from 1 on the first line and after a line break" do
      expect(described_class.position("abc", 0)).to eq(line: 1, column: 1)
      expect(described_class.position("abc", 2)).to eq(line: 1, column: 3)
      expect(described_class.position("ab\ncd", 4)).to eq(line: 2, column: 2)
    end

    it "counts characters, not bytes, even for a binary source" do
      expect(described_class.position("\u00e9=1\n".b, 2)).to eq(line: 1, column: 2)
    end
  end

  it "writes the score gates it was given into the report file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mutation.json")
      described_class.new(path).call(report_of(result_for(:killed)), score_gates: { threshold: 90 })
      expect(JSON.parse(File.read(path)).dig("saboteur", "scoreGates")).to eq("threshold" => 90)
    end
  end
end
