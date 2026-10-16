# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/pair_removal"
require "stringio"

RSpec.describe Saboteur::MutationSource::PairRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class Preloads\n  def apply(model)\n    #{body}\n  end\nend\n").first
  end

  def texts(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "removes one hash pair at a time, including the sole pair" do
    expect(texts("{a: :b, c: :d}").size).to eq(2)
    expect(texts("{a: :b}").first).to include("{}")
    expect(texts("{}")).to be_empty
  end

  it "removes each keyword association without changing positional preloads" do
    subject = subject_for("model.includes(:a, c: :d, e: :f)")
    model = Object.new
    def model.includes(*names, **nested) = [names, nested]
    original = Class.new { class_eval(subject.source) }.new.apply(model)
    found = source.mutations_for(subject)
    expect(found.size).to eq(2)
    found.each do |mutation|
      expect(mutation.operator).to eq("pair_removal")
      expect(mutation.source).to eq("pair_removal")
      expect(mutation.coarse).to be(false)
      changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new.apply(model)
      expect(changed.first).to eq([:a])
      expect { expect(changed).to eq(original) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  it "anchors the separator on the last positional argument, not an earlier one" do
    expect(texts("model.call(:a, :b, :c, d: 1)")).to eq(["def apply(model)\n    model.call(:a, :b, :c )\n  end"])
  end

  it "keeps separators valid in hashes and unparenthesized keyword calls" do
    ["{a: 1, b: 2,}", "{a: 1,}", "model.call :a, b: 1, c: 2", "model.call(a: 1, b: 2, &model)",
     "model.call(:a, c: :d)", "model.call :a, c: :d", "model.call(c: :d)",
     "model.call(c: :d,)", "model.call(:a, c: :d, &model)"].each do |body|
      expect(texts(body)).not_to be_empty
      expect(texts(body)).to all(satisfy { |text| Prism.parse(text).success? })
    end
  end

  it "preserves commas in strings and comments" do
    found = texts("{\"a,b\" => \"c,d\", # comma ,\n      :e => :f}")
    expect(found.size).to eq(2)
    expect(found.first).to include("# comma ,")
    expect(found.last).to include('"a,b" => "c,d"')
    expect(found).to all(satisfy { |text| Prism.parse(text).success? })
  end

  it "skips keyword splats, defaults, nested definitions and arid statements" do
    ["{**model}", "logger.info({a: 1})", "->(x = {a: 1}) { x }", "def inner; {a: 1}; end"].each do |body|
      expect(texts(body)).to be_empty, body
    end
  end

  it "visits callable bodies and nested values" do
    expect(texts("-> { {a: 1} }").size).to eq(1)
    expect(texts("{a: {b: 1}, c: 2}").size).to eq(3)
  end

  it "skips pairs containing heredocs" do
    expect(texts("{a: [<<~TEXT]}\nhi\nTEXT")).to be_empty
  end

  it "keeps digests stable after multibyte source shifts" do
    digests = ["", "# héllo\n"].map do |prefix|
      subject = subject_for("{a: 1, b: 2}", prefix: prefix)
      source.mutations_for(subject).map do |m|
        m.digest(subject_start: subject.start_byte, original_source: subject.file_source)
      end
    end
    expect(digests.first).to eq(digests.last)
  end

  it "lexes once per subject and handles whitespace around separators" do
    subject = subject_for("{a: 1 , b: 2}")
    expect(Prism).to receive(:lex).with(subject.file_source).once.and_call_original
    expect(source.mutations_for(subject).size).to eq(2)
  end

  it "handles whitespace and sole keyword separators" do
    expect(texts("{a: 1 , b: 2}")).to all(satisfy { |text| Prism.parse(text).success? })
    expect(texts("model.call(:a, c: :d)").first).to include("model.call(:a )")
    expect(texts("model.call(c: :d, &model)").first).to include("model.call( &model)")
    expect(texts("model.call c: :d, &model").first).to include("model.call  &model")
    expect(texts("model.call(:a, b: 1, c: 2)").last).to include("model.call(:a, b: 1 )")
  end

  it "preserves keyword splats when removing an ordinary pair" do
    expect(texts("{a: 1, **model}").first).to include("{ **model}")
    expect(texts("model.call(**model, a: 1)").first).to include("model.call(**model )")
  end

  it "has precise comma-token bounds" do
    subject = subject_for("{a: 1, b: 2}")
    tokens = Prism.lex(subject.file_source).value.map(&:first)
    ending = subject.node.body.body.first.elements.first.location.end_offset
    expect(source.send(:comma_between, ending, ending, tokens)).to be_nil
    expect(source.send(:comma_between, ending + 1, ending + 3, tokens)).to be_nil
    expect(source.send(:comma_between, ending - 1, ending + 1, tokens).slice).to eq(",")
  end

  it "appends pair proposals through builtin" do
    subject = subject_for("{a: :b}")
    expect(Saboteur::MutationSource::Builtin.new.mutations_for(subject).last.operator).to eq("pair_removal")
  end
  it "uses the normal coarse-first per-method cap" do
    subject = subject_for("{a: :b, c: :d}")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    all = candidates.for(subject)
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    selection = Saboteur::Engine::CandidateSelection.new(candidates: candidates, map: map, limit: all.size - 1,
                                                         diagnostics: diagnostics)
    selected = selection.for(subject)
    expect(selected).to eq(all[0...-1])
    expect(selected.first.first.coarse).to be(true)
    expect(selected.count { |mutation, _| mutation.operator == "pair_removal" }).to eq(1)
  end
end
