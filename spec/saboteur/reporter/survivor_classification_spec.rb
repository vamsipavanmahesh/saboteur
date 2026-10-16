# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivor classification labels (#192): why a survivor is worth looking at,
# as a label only - scores and the exit code never change.
RSpec.describe Saboteur::Reporter::SurvivorClassification do
  def survivor_for(source, from:, to:, covered_by: ["spec/a_spec.rb:1"], coarse: false)
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.b.index(from.b)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                              end_byte: at + from.bytesize, replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit], coarse:)
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

  it "withholds missing_test from coarse mutants: their covering list is a planned guess" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n",
                          from: ">=", to: ">", coarse: true)
    expect(described_class.label(result)).to be_nil
  end

  it "does not label an edit arid when it only starts on a logging line" do
    result = survivor_for("class A\n  def tell(msg)\n    logger.info(\n      msg)\n  end\nend\n",
                          from: "logger.info(\n      msg)", to: "nil", covered_by: [])
    expect(described_class.label(result)).to be_nil
  end

  it "labels an edit arid when every line it touches is arid" do
    result = survivor_for("class A\n  def tell(a, b)\n    puts a\n    puts b\n  end\nend\n",
                          from: "puts a\n    puts b", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "accepts a nondefault arid hint list" do
    result = survivor_for("class A\n  def tell(msg)\n    audit_log msg\n  end\nend\n",
                          from: "audit_log msg", to: "nil", covered_by: [])
    expect(described_class.label(result)).to be_nil
    expect(described_class.label(result, arid: ["audit_log"])).to eq("arid")
  end

  it "locates the edited line by bytes with multibyte text before and on the line" do
    result = survivor_for("class A\n  # caf\u00e9 menu\n  def tell(msg)\n    puts \"caf\u00e9 \#{msg}\"\n  end\nend\n",
                          from: "puts", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "never labels a non-survivor" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    killed = Saboteur::MutantResult.new(subject: result.subject, mutation: result.mutation,
                                        status: :killed, mutated_source: result.mutated_source)
    expect(described_class.label(killed)).to be_nil
  end
end
