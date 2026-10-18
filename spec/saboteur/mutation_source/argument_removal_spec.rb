# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/argument_removal"
require "stringio"

RSpec.describe Saboteur::MutationSource::ArgumentRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class Preloads\n  def apply(model)\n    #{body}\n  end\nend\n").first
  end

  def texts(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "removes each positional preload independently and a preload assertion kills each mutant" do
    subject = subject_for("model.includes(:a, :b, c: :d)")
    found = source.mutations_for(subject)
    expect(found.size).to eq(2)
    model = Object.new
    def model.includes(*names, **nested) = [names, nested]
    original = Class.new { class_eval(subject.source) }.new.apply(model)
    expect(original).to eq([%i[a b], { c: :d }])
    found.each do |mutation|
      expect(mutation.operator).to eq("argument_removal")
      expect(mutation.coarse).to be(false)
      changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new.apply(model)
      expect { expect(changed).to eq(original) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  it "handles first, middle, last and sole arguments without touching keyword pairs" do
    expect(texts("model.call(:a, :b, :c)")).to eq([
                                                    "def apply(model)\n    model.call( :b, :c)\n  end",
                                                    "def apply(model)\n    model.call(:a,  :c)\n  end",
                                                    "def apply(model)\n    model.call(:a, :b )\n  end"
                                                  ])
    expect(texts("model.call(:a)").first).to include("model.call()")
    expect(texts("model.call(a: :b)")).to be_empty
  end

  it "handles empty parentheses and leaves later calls alone" do
    expect(texts("model.call()")).to be_empty
    expect(texts("model.call(:a); model.call(:b, :c)").first).to include("model.call(); model.call(:b, :c)")
    expect(texts("model.call(:a, :b) { model.other(:c, :d) }")).to all(satisfy { |text| Prism.parse(text).success? })
  end

  it "does not confuse whitespace with the argument separators" do
    expect(texts("model.call(:a , :b)")).to all(satisfy { |text| Prism.parse(text).success? })
    expect(texts("model.call(:a , :b)").first).to include("model.call(  :b)")
    expect(texts("model.call(:a , :b)").last).to include("model.call(:a  )")
    expect(texts("model.call({a: 1, b: 2}, :c)").last).to include("model.call({a: 1, b: 2} )")
  end

  it "skips a positional container whose child is a heredoc" do
    expect(texts("model.call([<<~TEXT])\n      hi\n    TEXT")).to be_empty
    expect(texts("model.call(:a, -> { model.call() })")).to all(satisfy { |text| Prism.parse(text).success? })
  end

  it "preserves a forwarded block when removing its sole ordinary argument" do
    expect(texts("model.call(:a, &model)").first).to include("model.call( &model)")
  end

  it "uses actual separator tokens rather than commas in comments or strings" do
    found = texts("model.call(\"a,b\", # comma ,\n      :c)")
    expect(found.size).to eq(2)
    expect(found).to all(satisfy { |text| Prism.parse(text).success? })
    expect(found.first).to include("# comma ,")
    expect(found.last).to include('"a,b"')
  end

  it "finds only comma tokens within the requested byte interval" do
    subject = subject_for("model.call(:a, :b)")
    tokens = Prism.lex(subject.file_source).value.map(&:first)
    start = subject.node.body.body.first.arguments.arguments.first.location.end_offset
    expect(source.send(:comma_between, start + 1, start + 3, tokens)).to be_nil
    expect(source.send(:comma_between, start - 1, start + 1, tokens).slice).to eq(",")
  end

  it "lexes the file only once per subject, including nested calls" do
    subject = subject_for("model.call(:a, :b, model.other(:c, :d))")
    expect(Prism).to receive(:lex).with(subject.file_source).once.and_call_original
    expect(source.mutations_for(subject).size).to eq(5)
  end

  it "supports a trailing comma" do
    expect(texts("model.call(:a, :b,)")).to all(satisfy { |text| Prism.parse(text).success? })
    expect(texts("model.call(:a,)").first).to include("model.call()")
  end

  it "skips unparenthesized calls, splats, forwarding, index writes and heredoc arguments" do
    ["model.call :a", "model.call(*model)", "model[:a] = :b", "model.call(<<~TEXT)\n      hi\n    TEXT"].each do |body|
      expect(texts(body)).to be_empty, body
    end
  end

  it "does not enter arid calls, parameter defaults or nested method scopes" do
    ["logger.info(model.call(:a))", "->(value = model.call(:a)) { value }",
     "def inner; model.call(:a); end"].each { |body| expect(texts(body)).to be_empty, body }
    custom = described_class.new(arid: [/\Atrack\b/])
    expect(custom.mutations_for(subject_for("track(model.call(:a))"))).to be_empty
  end

  it "still visits callable bodies and nested argument expressions" do
    expect(texts("->(value = :a) { model.call(:b) }").size).to eq(1)
    expect(texts("model.call(model.other(:a), :b)").size).to eq(3)
  end

  it "keeps digests stable after a multibyte prefix shifts the method" do
    digests = ["", "# héllo\n"].map do |prefix|
      subject = subject_for("model.call(:a, :b)", prefix: prefix)
      source.mutations_for(subject).map do |mutation|
        mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
      end
    end
    expect(digests.first).to eq(digests.last)
  end

  it "appends ordinary argument proposals after existing builtin proposals" do
    subject = subject_for("model.includes(:a, :b)")
    found = Saboteur::MutationSource::Builtin.new(exclude_operators: ["argument_swap"]).mutations_for(subject)
    expect(found.last(2).map(&:operator)).to eq(%w[argument_removal argument_removal])
  end
  it "passes through the normal coarse-first per-method cap" do
    subject = subject_for("model.includes(:a, :b)")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    builtin = Saboteur::MutationSource::Builtin.new(exclude_operators: ["argument_swap"])
    candidates = Saboteur::Engine::Candidates.new([builtin], diagnostics)
    all = candidates.for(subject)
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    limit = all.size - 1
    selection = Saboteur::Engine::CandidateSelection.new(candidates: candidates, map: map, limit: limit,
                                                         diagnostics: diagnostics)
    selected = selection.for(subject)
    expect(selected).to eq(all.first(limit))
    expect(selected.first.first.coarse).to be(true)
    expect(selected.count { |mutation, _| mutation.operator == "argument_removal" }).to eq(1)
    expect(diagnostics.warnings).to include(/max_mutants_per_method/)
  end
end
