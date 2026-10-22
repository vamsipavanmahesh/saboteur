# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("Built for big suites"): "parallel coverage builds
# (`c.coverage_parts`) and a TracePoint recorder keep the map cheap". Cheap
# must not change a verdict, so each mode runs the people fixture end to end
# and its per-mutant results are compared with the default build.
RSpec.describe "coverage build modes (end to end)", :e2e do
  def run_with(setting)
    dir = copy_fixture("people")
    File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        #{setting}
      end
    RUBY
    saboteur(dir, "--all")
  end

  def verdicts(run)
    mutants(run).to_h { |mutant| [mutant["id"], mutant["status"]] }
  end

  def map_names(run)
    Dir.children(File.join(run.dir, ".saboteur")).grep(/\Acoverage-.*\.json\z/)
  end

  let(:default_run) { run_with("") }

  it "builds the map in parallel parts and gives every mutant the same verdict" do
    parts = run_with("c.coverage_parts = 2")

    expect(parts.err).to include("building coverage map (runs the suite once, in 2 parallel parts)")
    logs = Dir.children(File.join(parts.dir, ".saboteur"))
    expect(logs).to include("coverage-build-1.log", "coverage-build-2.log")
    expect(default_run.err).not_to include("parallel parts")
    expect(verdicts(parts)).not_to be_empty
    expect(verdicts(parts)).to eq(verdicts(default_run))
    expect(parts.status).to eq(default_run.status)
  end

  it "records with the trace recorder, a separate map, and the same verdicts" do
    trace = run_with('c.coverage_recorder = "trace"')

    expect(trace.status).to eq(default_run.status), other_outcomes(trace)
    expect(verdicts(trace)).to eq(verdicts(default_run))
    expect(map_names(trace)).not_to eq(map_names(default_run))
  end

  it "refuses an unknown recorder with a usage error naming the choices" do
    run = run_with('c.coverage_recorder = "magic"')

    expect(run.status).to eq(2)
    expect(run.err).to include("coverage_recorder must be one of: coverage, trace")
  end
end
