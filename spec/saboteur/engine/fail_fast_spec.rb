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
    results = distribution(->(subject_results) { subject_results == [:b] }).run(%i[a b c], [[1], [1], [1]])
    expect(calls).to eq(%i[a b])
    expect(results).to eq(%i[a b])
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
