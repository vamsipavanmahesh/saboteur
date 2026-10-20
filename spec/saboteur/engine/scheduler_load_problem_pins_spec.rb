# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The exact pair load_problem hands back: [skip reason, wrapper]. Each case
# asserts the whole pair, so a path that quietly returns a different shape or
# reason is caught even when the caller would read it the same way.
RSpec.describe Saboteur::Engine::Scheduler, "load_problem results" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }

  after do
    %i[LoadProblemPin LoadProblemParent LoadProblemChild].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end

  def scheduler(reevaluator: Saboteur::Execution::Reevaluator.new, verify_loaded: true)
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    described_class.new(config: Saboteur::Config.new({}), runner:, map:, reevaluator:, diagnostics:, verify_loaded:)
  end

  def loaded(source, id)
    subject = subjects_in(source, name: "load_problem_pin.rb").find { |s| s.id == id }
    load subject.file
    subject
  end

  it "returns no reason and no wrapper for a loaded method, whole-file subject or unverified run" do
    subject = loaded("class LoadProblemPin\n  def m(a)\n    a + 1\n  end\nend\n", "LoadProblemPin#m")
    expect(scheduler.send(:load_problem, subject)).to eq([nil, nil])
    expect(scheduler(verify_loaded: false).send(:load_problem, subject)).to eq([nil, nil])
    LoadProblemPin.class_eval("def m(a); a; end", __FILE__, __LINE__)
    whole = Saboteur::Execution::Reevaluator.new("nesting", whole_file: ["LoadProblemPin#m"])
    expect(scheduler(reevaluator: whole).send(:load_problem, subject)).to eq([nil, nil])
  end

  it "names a method that is not loaded, with no wrapper" do
    subject = loaded("class LoadProblemPin\n  def m(a)\n    a + 1\n  end\nend\n", "LoadProblemPin#m")
    LoadProblemPin.send(:remove_method, :m)
    expect(scheduler.send(:load_problem, subject)).to eq(["method not loaded", nil])
  end

  it "names an owner that is not loaded, with the whole-file hint and no wrapper" do
    subject = loaded("class LoadProblemPin\n  def m(a)\n    a + 1\n  end\nend\n", "LoadProblemPin#m")
    Object.send(:remove_const, :LoadProblemPin)
    result = scheduler.send(:load_problem, subject)
    expect(result.size).to eq(2)
    expect(result.first).to start_with("owner not loaded: ")
    expect(result.first).to end_with(described_class::WHOLE_FILE_HINT)
    expect(result.last).to be_nil
  end

  it "reports a method the class only inherits as not loaded instead of failing" do
    source = "class LoadProblemParent\n  def m(a)\n    a + 1\n  end\nend\n\n" \
             "class LoadProblemChild < LoadProblemParent\n  def other; end\nend\n"
    subject = loaded(source, "LoadProblemParent#m")
    child = subject.dup
    allow(child).to receive_messages(id: "LoadProblemChild#m", name: :m)
    reevaluator = Saboteur::Execution::Reevaluator.new
    allow(reevaluator).to receive(:resolve_owner).with(child).and_return(LoadProblemChild)
    expect(scheduler(reevaluator:).send(:load_problem, child)).to eq(["method not loaded", nil])
  end

  it "returns the wrapper beside a nil reason when a known def-time wrapper sits on the method" do
    subject = loaded("class LoadProblemPin\n  def m(a)\n    a + 1\n  end\nend\n", "LoadProblemPin#m")
    wrapped = LoadProblemPin.instance_method(:m)
    allow(wrapped).to receive(:source_location).and_return(["/elsewhere/sig.rb", 9])
    s = scheduler
    allow(s).to receive(:own_method).and_return(wrapped)
    allow(Saboteur::Execution::Wrapper).to receive(:around).with(wrapped, "/elsewhere/sig.rb").and_return(:sorbet)
    expect(s.send(:load_problem, subject)).to eq([nil, :sorbet])
  end
end
