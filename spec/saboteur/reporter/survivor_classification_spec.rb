# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivor classification labels (#192): why a survivor is worth looking at,
# as a label only - scores and the exit code never change.
RSpec.describe Saboteur::Reporter::SurvivorClassification do
  def survivor_for(source, from:, to:, covered_by: ["spec/a_spec.rb:1"])
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index(from)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                              end_byte: at + from.length, replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit], coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), covered_by: covered_by)
  end

  it "labels a covered survivor as a missing test" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    expect(described_class.label(result)).to eq("missing_test")
  end

  it "labels a bytecode-identical mutant as likely equivalent, before missing test" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: "18", to: "18")
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "labels a survivor on an arid line as arid, before missing test" do
    result = survivor_for("class A\n  def tell(msg)\n    puts msg\n  end\nend\n", from: "puts msg", to: "nil")
    expect(described_class.label(result)).to eq("arid")
  end

  it "leaves an uncovered survivor with no signal unlabeled" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: [])
    expect(described_class.label(result)).to be_nil
  end

  it "never labels a non-survivor" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    killed = Saboteur::MutantResult.new(subject: result.subject, mutation: result.mutation,
                                        status: :killed, mutated_source: result.mutated_source)
    expect(described_class.label(killed)).to be_nil
  end
end
