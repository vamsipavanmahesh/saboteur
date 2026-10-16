# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivor classification labels (#192): why a survivor is worth looking at,
# as a label only - scores and the exit code never change.
RSpec.describe Saboteur::Reporter::SurvivorClassification do
  def survivor_for(source, from:, to:, covered_by: ["spec/a_spec.rb:1"], coarse: false)
    survivor_for_edits(source, [[from, to]], covered_by: covered_by, coarse: coarse)
  end

  def survivor_for_edits(source, pairs, covered_by: ["spec/a_spec.rb:1"], coarse: false)
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    edits = pairs.map do |from, to|
      at = subject.file_source.b.index(from.b)
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                         end_byte: at + from.bytesize, replacement: to)
    end
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: edits, coarse: coarse)
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

  it "withholds missing_test from --test-command runs: the pseudo id is not real coverage (#305)" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: [Saboteur::Execution::ExternalRunner::PSEUDO_TEST])
    expect(described_class.label(result)).to be_nil
  end

  it "labels a survivor missing_test when real coverage sits next to the pseudo id (#305)" do
    covered = [Saboteur::Execution::ExternalRunner::PSEUDO_TEST, "spec/a_spec.rb:1"]
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: covered)
    expect(described_class.label(result)).to eq("missing_test")
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

  it "splices several edits from the end of the def back, however they are ordered" do
    # Both edits change length and compile to the original's instructions;
    # applied in the wrong order the second splice lands on stale offsets.
    result = survivor_for_edits("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n",
                                [["age >=", "(age) >="], ["18", "0x12"]])
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "sorts edits before splicing: unsorted edits must not land on stale offsets" do
    # argument_removal/pair_removal emit [argument, comma] with the comma
    # BEFORE the argument when the last one goes - unsorted by start_byte.
    # Without the sort the reversed splices run early-to-late and the
    # second lands two bytes off, mangling bytecode-identical code.
    result = survivor_for_edits("class A\n  def old?(age)\n    age >= 18 && age < 65\n  end\nend\n",
                                [["< 65", "< (65)"], ["18", "(18)"]])
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "reads the line an edit reaches into through its final byte" do
    # The edit ends on the "b" that opens the bar line: end_byte - 1 is
    # that "b", so the line search must start there and include the rest
    # of the bar line. One byte earlier finds the newline inside the edit
    # and drops the bar line entirely.
    result = survivor_for("class A\n  def m\nfoo\nbar\n  end\nend\n",
                          from: "foo\nb", to: "nil")
    expect(described_class.label(result, arid: ["\\Afoo\\z"])).to eq("missing_test")
  end

  it "compiles with the subject's frozen-string-literal setting" do
    result = survivor_for("# frozen_string_literal: true\nclass A\n  def tell(msg)\n    puts msg\n  end\nend\n",
                          from: "puts msg", to: "nil")
    checker = Saboteur::Engine::BytecodeEquivalence.new
    allow(Saboteur::Engine::BytecodeEquivalence).to receive(:new).and_return(checker)
    expect(checker).to receive(:equivalent?).with(anything, anything, frozen_string_literal: true)
                                            .and_call_original
    described_class.label(result)
  end

  it "is not arid when any one edit of several is off an arid line" do
    result = survivor_for_edits("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                                [["puts a", "nil"], [">=", ">"]], covered_by: [])
    expect(described_class.label(result)).to be_nil
  end

  it "is not arid for a zero-width edit on a blank line" do
    source = "class A\n  def m(a)\n\n    puts a\n  end\nend\n"
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = source.b.index("\n\n") + 1
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                              end_byte: at, replacement: "x")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit], coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits), covered_by: [])
    expect(described_class.label(result)).to be_nil
  end

  it "extracts the edited line when nothing precedes it, not even a newline" do
    # A one-line class: the edit sits on the file's first and only line.
    result = survivor_for("class A; def m; puts a; end; end\n",
                          from: "puts a", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ["\\Aclass A; def m; puts a; end; end\\z"])).to eq("arid")
  end

  it "extracts the edited line at the end of a file without a trailing newline" do
    # The edit ends on the file's LAST line (the def's own end, the class
    # end sharing the line) and the file has no trailing newline, so the
    # bytesize fallback is what finds the line end.
    result = survivor_for("class A\n  def m\n    puts a\n  end end",
                          from: "puts a\n  end", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ["\\Aputs a\\z", "\\Aend end\\z"])).to eq("arid")
  end

  it "reads only the edited lines when the edit ends at the newline" do
    result = survivor_for("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                          from: "puts a\n", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "reads every line an edit reaches into" do
    result = survivor_for("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                          from: "puts a\n    a", to: "nil", covered_by: [])
    expect(described_class.label(result)).to be_nil
  end

  it "matches multibyte arid patterns against the decoded line" do
    result = survivor_for("class A\n  def tell\n    note \"caf\u00e9\"\n  end\nend\n",
                          from: "note", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ['\Anote "caf\u00e9"'])).to eq("arid")
  end

  it "scrubs an invalid byte sequence on the edited line instead of raising" do
    edit = Saboteur::MutationSource::Edit.new(file: "x.rb", start_byte: 0, end_byte: 4,
                                              replacement: "nil")
    subject = instance_double(Saboteur::Subject, file_source: "puts a # caf\xC3".b)
    lines = described_class.send(:edited_lines, subject, edit)
    expect(lines).to eq(["puts a # caf\uFFFD"])
    expect(lines.first.valid_encoding?).to be(true)
  end

  it "never labels a non-survivor" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    killed = Saboteur::MutantResult.new(subject: result.subject, mutation: result.mutation,
                                        status: :killed, mutated_source: result.mutated_source)
    expect(described_class.label(killed)).to be_nil
  end
end
