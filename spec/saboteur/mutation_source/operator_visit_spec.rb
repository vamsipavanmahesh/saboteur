# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::OperatorVisit do
  let(:operators) do
    Saboteur::MutationSource.constants.map { |name| Saboteur::MutationSource.const_get(name) }
                            .select { |klass| klass.is_a?(Class) && klass.include?(described_class) }
  end

  let(:subject_under_test) do
    subjects_in("class Walk\n  def m(x)\n    result = x ? \"a\" : \"b\"\n    other = true\n  end\nend\n").first
  end

  def offsets(operator, arid)
    operator.new(arid: arid).mutations_for(subject_under_test).flat_map { |m| m.edits.map(&:start_byte) }.sort
  end

  it "is included by the condition and literal operators too (#891)" do
    expect(operators).to include(Saboteur::MutationSource::ConditionNegation,
                                 Saboteur::MutationSource::LiteralReplacement)
  end

  it "applies an arid pattern to whole statements for every operator" do
    first_statement_end = subject_under_test.file_source.index("other = true")
    operators.each do |operator|
      all = offsets(operator, [])
      # Matches the ternary inside the statement, not the statement: nothing is suppressed.
      expect(offsets(operator, ['\Ax \?'])).to eq(all), operator.name
      # Matches the whole first statement: only its own mutants go.
      expect(offsets(operator, ['\Aresult'])).to eq(all.select { |byte| byte >= first_statement_end }), operator.name
    end
  end

  it "negates the ternary condition and flips the other statement's literal, both beside the arid inner expression" do
    arid = ['\Ax \?']
    negations = offsets(Saboteur::MutationSource::ConditionNegation, arid)
    literals = offsets(Saboteur::MutationSource::LiteralReplacement, arid)
    expect(negations.size).to eq(1)
    expect(literals.size).to eq(3)
  end

  it "applies the default logger arid to whole statements: a logger inside another call is no longer skipped" do
    builtin = Saboteur::MutationSource::Builtin.new(operators: %w[condition_negation literal_string literal_boolean])
    skipped = subjects_in("class W\n  def m\n    logger.info(\"x\") ? 1 : 2\n  end\nend\n").first
    nested = subjects_in("class W\n  def m\n    foo(logger.info(\"x\") ? 1 : 2)\n  end\nend\n").first
    expect(builtin.mutations_for(skipped)).to be_empty
    expect(builtin.mutations_for(nested).map(&:operator)).to include("condition_negation")
  end
end
