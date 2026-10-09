# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Before mutating a method, the scheduler checks that the method Ruby runs is
# the one in the file: otherwise re-evaluating it would change nothing (or
# the wrong thing) and every mutant would survive for no reason.
RSpec.describe Saboteur::Engine::Scheduler, "load check" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:runner) { double("runner", run: Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1)) }

  after { Object.send(:remove_const, :LoadCheckTarget) if defined?(LoadCheckTarget) }

  # Writes the source, loads it, and schedules the subject with the given id.
  def schedule(source, id, extra: nil)
    subject = subjects_in(source, name: "load_check_target.rb").find { |s| s.id == id }
    load subject.file
    instance_eval(extra) if extra
    lines = (subject.start_line..subject.end_line).to_h { |line| [line, ["t1"]] }
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => lines }, tests: ["t1"])
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    scheduler.call(subject, candidates.for(subject))
  end

  def reasons(results)
    results.map(&:reason).uniq
  end

  it "runs a method whose loaded definition is the one in the file" do
    results = schedule("class LoadCheckTarget\n  def m(a)\n    a + 1\n  end\nend\n", "LoadCheckTarget#m")
    expect(reasons(results)).not_to include(a_string_matching(/not loaded|shadowed/))
    expect(runner).to have_received(:run).at_least(:once)
  end

  it "runs a singleton method the same way" do
    results = schedule("class LoadCheckTarget\n  def self.m(a)\n    a + 1\n  end\nend\n", "LoadCheckTarget.m")
    expect(reasons(results)).not_to include(a_string_matching(/not loaded|shadowed/))
  end

  it "skips a method that was removed after loading" do
    results = schedule("class LoadCheckTarget\n  def m(a)\n    a + 1\n  end\nend\n", "LoadCheckTarget#m",
                       extra: "LoadCheckTarget.send(:remove_method, :m)")
    expect(reasons(results)).to eq(["method not loaded"])
  end

  it "skips the earlier of two definitions: Ruby runs the later one" do
    source = "class LoadCheckTarget\n  def m(a)\n    a + 1\n  end\n\n  def m(a)\n    a + 2\n  end\nend\n"
    subjects = subjects_in(source, name: "load_check_target.rb").select { |s| s.id == "LoadCheckTarget#m" }
    expect(subjects.size).to eq(2)
    results = schedule(source, "LoadCheckTarget#m") # find returns the first (earlier) one
    expect(reasons(results).first).to start_with("shadowed definition (runtime method at ")
  end

  it "looks past a prepended module to the class's own method" do
    results = schedule("class LoadCheckTarget\n  def m(a)\n    a + 1\n  end\nend\n", "LoadCheckTarget#m",
                       extra: "LoadCheckTarget.prepend(Module.new { def m(a) = super })")
    expect(reasons(results)).not_to include(a_string_matching(/not loaded|shadowed/))
  end
end
