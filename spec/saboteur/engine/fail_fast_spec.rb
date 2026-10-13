# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution, "fail fast" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:calls) { [] }
  let(:scheduler) do
    calls_seen = calls
    Class.new do
      define_method(:call) do |subject, _list|
        calls_seen << subject
        [subject]
      end
    end.new
  end

  def distribution(stop_after)
    described_class.new(jobs: 1, scheduler: scheduler, diagnostics: diagnostics, cache: nil, stop_after: stop_after)
  end

  it "stops before the next subject once the callable says so" do
    run = distribution(->(subject_results) { subject_results == [:b] })
    results = run.run(%i[a b c], [[1], [1], [1]])
    expect(calls).to eq(%i[a b])
    expect(results).to eq(%i[a b])
    expect(run.unreached).to eq([:c])
  end

  it "has no unreached subjects when the last subject triggers the stop, or nothing does" do
    last = distribution(->(subject_results) { subject_results == [:c] })
    last.run(%i[a b c], [[1], [1], [1]])
    expect(last.unreached).to eq([])
    plain = distribution(nil)
    plain.run(%i[a b], [[1], [1]])
    expect(plain.unreached).to eq([])
  end

  it "runs every subject without a stop condition" do
    distribution(nil).run(%i[a b c], [[1], [1], [1]])
    expect(calls).to eq(%i[a b c])
  end
end

RSpec.describe Saboteur::IgnoreList, "accepts?" do
  it "accepts only survivors listed by subject and digest" do
    result = result_for(:survived)
    list = described_class.new([described_class::Entry.new(subject: result.subject.id, mutation: result.digest,
                                                           reason: "equivalent")])
    expect(list.accepts?(result)).to be(true)
    expect(described_class.new([]).accepts?(result)).to be(false)
    expect(list.accepts?(result_for(:killed))).to be(false)
  end
end

RSpec.describe Saboteur::Config, "fail_fast" do
  it "refuses fail_fast with more than one job" do
    expect { described_class.load(root: Dir.pwd, overrides: { "fail_fast" => true, "jobs" => 2 }) }
      .to raise_error(Saboteur::ConfigError, /fail_fast needs jobs 1/)
  end
end

RSpec.describe Saboteur::Engine, "fail_fast with baseline evidence" do
  it "refuses, because evidence certifies the whole selection" do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    config = Saboteur::Config.load(root: Dir.pwd, overrides: { "fail_fast" => true })
    expect { described_class.new(config, capture_evidence: true).call }
      .to raise_error(Saboteur::ConfigError, /fail_fast cannot be used with baseline evidence/)
  end
end

RSpec.describe Saboteur::Engine, "fail-fast check" do
  let(:err) { StringIO.new }
  let(:ignore_list) { instance_double(Saboteur::IgnoreList, accepts?: false) }

  def check_for(values)
    described_class.new(Saboteur::Config.new(values), err: err).send(:fail_fast_check, ignore_list)
  end

  it "is absent unless fail_fast is configured" do
    expect(check_for({})).to be_nil
  end

  it "stops, and says so, after a subject with an unaccepted survivor" do
    survivor = Struct.new(:survived?).new(true)
    expect(check_for("fail_fast" => true).call([survivor])).to be(true)
    expect(err.string).to include("--fail-fast: stopping after the first subject with a survivor")
  end

  it "keeps going when every survivor is accepted or none survived" do
    check = check_for("fail_fast" => true)
    expect(check.call([Struct.new(:survived?).new(false)])).to be(false)
    allow(ignore_list).to receive(:accepts?).and_return(true)
    expect(check.call([Struct.new(:survived?).new(true)])).to be(false)
    expect(err.string).to be_empty
  end
end
