# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The engine flags whole-suite runs so the coverage store can remember the
# map for later scoped runs (review C1). Scope flags (--since, subjects,
# explicit tests without inferred specs) all disqualify the run.
RSpec.describe Saboteur::Engine, "whole-suite run detection" do
  def build_engine(settings = {})
    described_class.new(Saboteur::Config.new(settings, root: Dir.pwd), err: StringIO.new, verbose: false,
                                                                       quiet_start: false)
  end

  it "is a whole-suite run with no scope flags" do
    expect(build_engine.send(:whole_suite_run?)).to be(true)
  end

  it "is not a whole-suite run with --since" do
    expect(build_engine("since" => "main").send(:whole_suite_run?)).to be(false)
  end

  it "is not a whole-suite run with explicit subjects" do
    expect(build_engine("subjects" => ["People::Person"]).send(:whole_suite_run?)).to be(false)
  end

  it "is not a whole-suite run with explicit tests and no inferred specs" do
    expect(build_engine("tests" => ["spec/person_spec.rb"]).send(:whole_suite_run?)).to be(false)
  end

  it "is not a whole-suite run when specs were inferred: inference is a selection (#1286)" do
    engine = build_engine("tests" => ["spec/person_spec.rb"])
    engine.instance_variable_set(:@guessed_tests, ["spec/person_spec.rb"])
    expect(engine.send(:whole_suite_run?)).to be(false)
    expect(engine.scoped_selection?).to be(true)
  end

  it "is not a whole-suite run once specs were inferred, even with no explicit tests (#1286)" do
    engine = build_engine
    engine.instance_variable_set(:@guessed_tests, ["spec/person_spec.rb"])
    expect(engine.send(:whole_suite_run?)).to be(false)
  end

  it "is not scoped without scope flags and is scoped with any of them" do
    expect(build_engine.scoped_selection?).to be(false)
    expect(build_engine("since" => "main").scoped_selection?).to be(true)
  end

  it "builds the coverage store once, flagged as a whole-suite run" do
    store = instance_double(Saboteur::Engine::CoverageStore)
    integration = instance_double(Saboteur::Integration::RSpec)
    engine = build_engine
    allow(engine).to receive(:supervisor).and_return(nil)
    expect(Saboteur::Engine::CoverageStore).to receive(:new).once
                                                            .with(hash_including(whole_suite_run: true))
                                                            .and_return(store)

    expect(engine.send(:coverage_store, integration, {})).to be(store)
    expect(engine.send(:coverage_store, integration, {})).to be(store)
  end
end

RSpec.describe Saboteur::Engine, "whole-suite map readers (review C1)" do
  def build_engine(settings = {})
    described_class.new(Saboteur::Config.new(settings, root: Dir.pwd), err: StringIO.new, verbose: false,
                                                                       quiet_start: false)
  end

  it "looks up the whole-suite map only when caching is on" do
    expect(build_engine("cache" => true).whole_suite_map_lookup?).to be(true)
    expect(build_engine("cache" => false).whole_suite_map_lookup?).to be(false)
  end

  it "reads the run's own selection map off the coverage store, nil before one exists" do
    fetched = instance_double(Saboteur::Selection::CoverageMap)
    store = instance_double(Saboteur::Engine::CoverageStore, fetched_map: fetched)
    engine = build_engine

    expect(engine.run_coverage_map).to be_nil
    engine.instance_variable_set(:@coverage_store, store)
    expect(engine.run_coverage_map).to be(fetched)
  end

  it "reads the cached whole-suite map off the coverage store, nil before one exists" do
    map = instance_double(Saboteur::Selection::CoverageMap)
    store = instance_double(Saboteur::Engine::CoverageStore, whole_suite_map: map)
    engine = build_engine

    expect(engine.whole_suite_coverage_map).to be_nil
    engine.instance_variable_set(:@coverage_store, store)
    expect(engine.whole_suite_coverage_map).to be(map)
  end
end
