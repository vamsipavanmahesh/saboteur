# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Candidates do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }

  # A mutation source that proposes whatever replacements it is given for
  # the `a + 1` expression.
  def source_proposing(*replacements, coarse: false)
    owner = subject_under_test
    Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        at = subject.file_source.index("a + 1")
        replacements.map do |text|
          edit = Saboteur::MutationSource::Edit.new(file: owner.file, start_byte: at, end_byte: at + 5,
                                                    replacement: text)
          Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit],
                                                 coarse: coarse)
        end
      end
    end.new
  end

  def candidates(*sources)
    described_class.new(sources, diagnostics).for(subject_under_test)
  end

  it "applies each mutation and returns the mutated method text" do
    expect(candidates(source_proposing("a - 1")).map(&:last)).to eq(["def m(a)\n    a - 1\n  end"])
  end

  it "drops mutations that change nothing or repeat an earlier one" do
    expect(candidates(source_proposing("a + 1", "a - 1", "a - 1")).size).to eq(1)
  end

  it "drops and counts mutations that do not parse" do
    expect(candidates(source_proposing("a +"))).to be_empty
    expect(diagnostics.invalid_mutations).to eq(1)
    expect(diagnostics.generation_events.map(&:reason)).to eq(["invalid_syntax"])
  end

  it "drops a mutation that compiles to the original's bytecode and records why" do
    expect(candidates(source_proposing("(a + 1)", "a - 1")).map(&:last)).to eq(["def m(a)\n    a - 1\n  end"])
    expect(diagnostics.generation_events.map(&:reason)).to eq(["equivalent_bytecode"])
  end

  it "keeps literal string mutants whose text looks like hex or a parenthesised number" do
    subject_under_test = subjects_in("class K\n  def m\n    \"0xdead(123)\"\n  end\nend\n").first
    owner = subject_under_test
    source = Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        at = subject.file_source.index("\"0xdead(123)\"")
        ["\"0xbeef(123)\"", "\"0xdead(124)\"", "\"\""].map do |text|
          edit = Saboteur::MutationSource::Edit.new(file: owner.file, start_byte: at, end_byte: at + 13,
                                                    replacement: text)
          Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "literal_string", edits: [edit])
        end
      end
    end.new

    found = described_class.new([source], diagnostics).for(subject_under_test)

    expect(found.size).to eq(3)
    expect(diagnostics.generation_events.map(&:reason)).not_to include("equivalent_bytecode")
  end

  it "keeps a mutant that only flips the sign of a zero, bare or nested in a literal" do
    [["0.0", "-0.0"], ["[0.0]", "[-0.0]"], ["{ a: 0.0 }", "{ a: -0.0 }"]].each do |original, mutated|
      owner = subjects_in("class K\n  def m\n    #{original}\n  end\nend\n").first
      source = Class.new(Saboteur::MutationSource::Base) do
        define_method(:mutations_for) do |subject|
          at = subject.file_source.index(original)
          edit = Saboteur::MutationSource::Edit.new(file: owner.file, start_byte: at, end_byte: at + original.size,
                                                    replacement: mutated)
          [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "literal_float", edits: [edit])]
        end
      end.new

      found = described_class.new([source], diagnostics).for(owner)

      expect(found.size).to eq(1), "#{original} -> #{mutated} was dropped as equivalent"
    end
  end

  it "compares bytecode under the file's frozen_string_literal comment" do
    bytecode = instance_double(Saboteur::Engine::BytecodeEquivalence, equivalent?: false)
    text = "# frozen_string_literal: true\nclass K\n  def m(a)\n    a + 1\n  end\nend\n"
    frozen_subject = subjects_in(text).first
    source = Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        at = subject.file_source.index("a + 1")
        edit = Saboteur::MutationSource::Edit.new(file: frozen_subject.file, start_byte: at, end_byte: at + 5,
                                                  replacement: "a - 1")
        [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])]
      end
    end.new

    described_class.new([source], diagnostics, bytecode: bytecode).for(frozen_subject)

    expect(bytecode).to have_received(:equivalent?).with(anything, anything, frozen_string_literal: true)
  end

  it "puts coarse mutations first" do
    found = candidates(source_proposing("a - 1"), source_proposing("nil", coarse: true))
    expect(found.map { |mutation, _| mutation.coarse }).to eq([true, false])
  end

  it "drops a mutation with an edit outside the method and warns" do
    outside = Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: 0, end_byte: 5, replacement: "x")
        [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "bad", edits: [edit])]
      end
    end.new
    expect(candidates(outside)).to be_empty
    expect(diagnostics.warnings.first).to include("outside")
    expect(diagnostics.generation_events.map(&:reason)).to eq(["invalid_edit"])
  end

  it "records typed dropped proposals without parsing warning text" do
    candidates(source_proposing("a + 1", "a - 1", "a - 1", "a +"))

    expect(diagnostics.generation_events.map(&:reason)).to eq(%w[unchanged duplicate invalid_syntax])
    expect(diagnostics.generation_events.map(&:subject)).to all(eq("K#m"))
    expect(diagnostics.generation_events.map(&:source)).to all(eq("builtin"))
    expect(diagnostics.generation_events.map(&:operator)).to all(eq("test"))
    expect(diagnostics.generation_events).to all(be_frozen)
  end

  it "records empty generation as unverified, not proof of a supported exclusion" do
    candidates(source_proposing)

    expect(diagnostics.generation_events.map(&:reason)).to eq(["empty_generation"])
    expect(diagnostics.generation_events.first.operator).to be_nil
    expect(diagnostics.generation_events.first.source).to eq("anonymous")
  end

  it "uses a named source identity for empty generation" do
    source = source_proposing
    allow(source).to receive(:name).and_return("custom_source")
    candidates(source)

    expect(diagnostics.generation_events.first.source).to eq("custom_source")
  end

  it "records invalid subject syntax without asking mutation sources for proposals" do
    allow(subject_under_test).to receive(:source).and_return("def broken(")
    source = source_proposing("a - 1")
    expect(source).not_to receive(:mutations_for)

    expect(candidates(source)).to be_empty
    expect(diagnostics.generation_events.map(&:reason)).to eq(["invalid_subject_syntax"])
    expect(diagnostics.generation_events.first.source).to eq("subject")
  end

  it "retains empty generation for a duck-typed source without a name method" do
    source = Object.new
    def source.mutations_for(_subject)
      []
    end
    candidates(source)

    expect(diagnostics.generation_events.first.source).to eq("anonymous")
  end

  it "retains immutable evidence snapshots on the internal report" do
    candidates(source_proposing("a +"))
    report = Saboteur::Report.new(results: [], subjects: [subject_under_test], wall_time: 0, root: "/tmp",
                                  generation_events: diagnostics.generation_events, omissions: diagnostics.omissions)
    diagnostics.record_generation(subject_under_test, source: "other", reason: "empty_generation")

    expect(report.generation_events.map(&:reason)).to eq(["invalid_syntax"])
    expect(report.generation_events).to be_frozen
    expect(report.omissions).to be_frozen
  end

  describe ".build_sources (external)" do
    it "loads a namespaced source class from a file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "deep.rb"),
                   "module DeepSources\n  class One < Saboteur::MutationSource::Base\n  end\nend\n")
        config = Saboteur::Config.new({ "sources" => ["deep.rb:DeepSources::One"] }, root: dir)
        expect(described_class.build_sources(config).first).to be_a(DeepSources::One)
      end
    end
  end

  describe ".build_sources" do
    it "builds the builtin source and rejects an entry without a class name" do
      config = Saboteur::Config.new({ "sources" => ["builtin"] })
      expect(described_class.build_sources(config).map(&:name)).to eq(["builtin"])
      bad = Saboteur::Config.new({ "sources" => ["lib/my_source.rb"] })
      expect { described_class.build_sources(bad) }.to raise_error(Saboteur::ConfigError, /path.rb:ClassName/)
    end
  end
end

RSpec.describe Saboteur::Engine::Candidates, "hazard guard (issue #102)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:danger_subject) do
    subjects_in("class K\n  def m\n    FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))\n  end\nend\n").first
  end

  it "suppresses hazardous mutants and records each suppression" do
    candidates = described_class.new([Saboteur::MutationSource::Builtin.new], diagnostics,
                                     hazard_guard: Saboteur::MutationSource::HazardGuard.new)
    operators = candidates.for(danger_subject).map(&:first).map(&:operator)
    expect(operators).to include("body_nil", "body_raise")
    expect(operators).not_to include("literal_string", "argument_removal")
    expect(diagnostics.hazard_suppressions).to be_positive
    expect(diagnostics.generation_events.map(&:reason)).to include("hazardous")
  end

  it "keeps hazardous mutants when no guard is given" do
    candidates = described_class.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    operators = candidates.for(danger_subject).map(&:first).map(&:operator)
    expect(operators).to include("literal_string")
    expect(diagnostics.hazard_suppressions).to eq(0)
  end
end
