# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# A scoped run that has survivors and no whole-suite map says so once (#1286).
RSpec.describe Saboteur::CLI::WholeSuiteMapLookup do
  let(:err) { StringIO.new }
  let(:cli) { Saboteur::CLI.new([], out: StringIO.new, err: err) }
  let(:notice) do
    "saboteur: survivors unconfirmed: no whole-suite coverage map; run `saboteur run --all` to build one\n"
  end
  let(:survivor_report) { report_of(result_for(:survived)) }
  let(:killed_report) { report_of(result_for(:killed)) }
  let(:map) { instance_double(Saboteur::Selection::CoverageMap) }

  def engine(lookup: true, scoped: true, map: nil)
    instance_double(Saboteur::Engine, whole_suite_map_lookup?: lookup, scoped_selection?: scoped,
                                      whole_suite_coverage_map: map)
  end

  def lookup(report, engine) = cli.send(:whole_suite_map_for, engine, report)

  it "notices a scoped run with survivors and no map, and returns no map" do
    expect(lookup(survivor_report, engine)).to be_nil
    expect(err.string).to eq(notice)
  end

  it "stays silent when no survivor is left" do
    lookup(killed_report, engine)
    expect(err.string).to be_empty
  end

  it "stays silent when the run was not scoped" do
    lookup(survivor_report, engine(scoped: false))
    expect(err.string).to be_empty
  end

  it "stays silent when a whole-suite map exists, and returns it" do
    expect(lookup(survivor_report, engine(map: map))).to equal(map)
    expect(err.string).to be_empty
  end

  it "stays silent without a cache, where no map could be built, and returns the no-lookup marker" do
    expect(lookup(survivor_report, engine(lookup: false))).to equal(Saboteur::Reporter::SurvivorList::NO_WHOLE_SUITE_LOOKUP)
    expect(err.string).to be_empty
  end

  it "stays silent and safe without an engine" do
    expect(lookup(survivor_report, nil)).to equal(Saboteur::Reporter::SurvivorList::NO_WHOLE_SUITE_LOOKUP)
    expect(err.string).to be_empty
  end
end
