# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The --test-command mode takes its own pipeline: no test inference, one
# job, mutants decided by the command's exit status (#140, #305).
RSpec.describe "Engine external test-command pipeline" do
  # Under the repo's own dogfood these specs run INSIDE a saboteur child;
  # Engine#call refuses that, so the markers go for the example's duration.
  before do
    stub_const("ENV", ENV.to_h.except(Saboteur::Execution::Supervisor::CHILD_ENV,
                                      Saboteur::Execution::ExternalRunner::CHILD_MARKER))
    # The external pipeline never boots. Without this, a flipped dispatch
    # condition walks every example through a real (slow) boot and the
    # mutant run reports Timeout instead of Killed (#305 dogfood).
    allow(Saboteur::Engine::Boot).to receive(:new).and_raise("the external pipeline must not boot")
  end

  def with_fixture
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "k.rb"),
                 "class K\n  def m(a)\n    a + 1\n  end\n  def n(b)\n    b * 2\n  end\nend\n")
      yield root
    end
  end

  it "skips test selection, forces one job, and reports the pseudo test" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true", "jobs" => 4 }, root: root)
      engine = Saboteur::Engine.new(config)
      expect(engine).not_to receive(:select_tests)
      jobs_seen = nil
      allow(Saboteur::Engine::Distribution).to receive(:new).and_wrap_original do |method, **kwargs|
        jobs_seen = kwargs[:jobs]
        method.call(**kwargs)
      end
      report = engine.call
      expect(jobs_seen).to eq(1)
      expect(report.results).not_to be_empty
      expect(report.results.flat_map(&:executed)).to all(eq("(test command)"))
    end
  end

  # Kills must be real: the command fails on the mutant but passes the
  # neutral check - never a kill checked against itself (#305 DevRel).
  it "kills the mutant the command detects and passes the neutral check" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "grep -q 'a + 1' lib/k.rb" }, root: root)
      report = Saboteur::Engine.new(config).call
      statuses = report.results.map(&:status)
      expect(statuses).to include(:killed)
      expect(statuses).to include(:survived)
      expect(statuses).not_to include(:error)
    end
  end

  # The preflight wait hitting the overall run budget is a budget stop,
  # not a command failure: early stop max_duration, no preflight error
  # (#305 QA).
  it "records a budget stop when the budget cuts the preflight" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "sleep 5", "max_duration" => 0.2 }, root: root)
      report = Saboteur::Engine.new(config).call
      expect(report.early_stop&.reason).to eq("max_duration")
      expect(report.results).to eq([])
    end
  end

  # The external path is chosen by the command alone: the in-process boot
  # never runs (#305 dogfood).
  it "never boots in-process when a test command is set" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true" }, root: root)
      expect(Saboteur::Engine::Boot).not_to receive(:new)
      Saboteur::Engine.new(config).call
    end
  end

  it "announces the exact external-mode tradeoff (#305 dogfood)" do
    with_fixture do |root|
      err = StringIO.new
      config = Saboteur::Config.new({ "test_command" => "true" }, root: root)
      Saboteur::Engine.new(config, err: err).call
      expect(err.string).to include("external test command: true " \
                                    "(serial, no coverage, unsandboxed, mutants applied in a disposable copy)")
    end
  end

  it "skips mutation entirely when nothing is in scope (#305 dogfood)" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true", "include" => ["lib/nope/**/*.rb"] }, root: root)
      engine = Saboteur::Engine.new(config)
      expect(engine).not_to receive(:mutate_external)
      expect(engine.call.results).to eq([])
    end
  end

  it "applies the ignore list with the unscoped digests and keeps its warnings (#305 dogfood)" do
    with_fixture do |root|
      seen = nil
      allow_any_instance_of(Saboteur::IgnoreList).to receive(:apply).and_wrap_original do |method, results, **kwargs|
        seen = kwargs
        method.call(results, **kwargs) + ["marker-warning"]
      end
      config = Saboteur::Config.new({ "test_command" => "true" }, root: root)
      report = Saboteur::Engine.new(config).call
      expect(seen).to have_key(:unscoped_digests)
      expect(report.warnings).to include("marker-warning")
    end
  end

  # The external scheduler is wired for the no-coverage mode: pseudo map,
  # reevaluator honoring whole_file, diagnostics, the run budget as its
  # deadline, and no loaded-suite verification (#305 dogfood).
  it "wires the scheduler for the external mode (#305 dogfood)" do
    with_fixture do |root|
      seen = nil
      allow(Saboteur::Engine::Scheduler).to receive(:new).and_wrap_original do |method, **kwargs|
        seen = kwargs
        method.call(**kwargs)
      end
      config = Saboteur::Config.new({ "test_command" => "true", "whole_file" => true, "max_duration" => 60 },
                                    root: root)
      Saboteur::Engine.new(config).call
      expect(seen[:map]).to be_a(Saboteur::Selection::ExternalTestMap)
      expect(seen[:reevaluator]).to be_a(Saboteur::Execution::Reevaluator)
      expect(seen[:diagnostics]).not_to be_nil
      expect(seen[:deadline]).not_to be_nil
      expect(seen[:verify_loaded]).to be(false)
    end
  end

  it "forwards whole_file to the reevaluator (#305 dogfood)" do
    with_fixture do |root|
      calls = []
      allow(Saboteur::Execution::Reevaluator).to receive(:new).and_wrap_original do |method, *args, **kwargs|
        calls << kwargs
        method.call(*args, **kwargs)
      end
      config = Saboteur::Config.new({ "test_command" => "true", "whole_file" => ["vendor/**"] }, root: root)
      Saboteur::Engine.new(config).call
      expect(calls).to include(hash_including(whole_file: ["vendor/**"]))
    end
  end

  it "runs nothing when every subject ends up without candidates (#305 dogfood)" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true" }, root: root)
      engine = Saboteur::Engine.new(config)
      allow(engine).to receive(:candidate_lists) { |subjects, _, _| subjects.map { [] } }
      expect(engine).not_to receive(:run_candidates)
      expect(engine.call.results).to eq([])
    end
  end

  # The preflight deadline is its own baseline_timeout slice or the run
  # budget, whichever is SOONER (#305 dogfood).
  describe "preflight deadline" do
    def engine_for(config_hash)
      with_fixture do |root|
        yield Saboteur::Engine.new(Saboteur::Config.new({ "test_command" => "true" }.merge(config_hash),
                                                        root: root))
      end
    end

    before do
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1000.0)
    end

    it "sizes its own slice by the configured baseline_timeout (300 by default)" do
      engine_for({}) do |engine|
        allow(engine).to receive(:budget_deadline).and_return(nil)
        expect(engine.send(:preflight_deadline)).to eq(1300.0)
      end
    end

    it "honors a configured baseline_timeout" do
      engine_for({ "baseline_timeout" => 5 }) do |engine|
        allow(engine).to receive(:budget_deadline).and_return(nil)
        expect(engine.send(:preflight_deadline)).to eq(1005.0)
      end
    end

    it "takes the sooner of its own slice and the run budget" do
      engine_for({ "baseline_timeout" => 5 }) do |engine|
        allow(engine).to receive(:budget_deadline).and_return(1003.0)
        expect(engine.send(:preflight_deadline)).to eq(1003.0)
      end
    end
  end

  # condition_true / body_true / chain_removal on the dispatch or its
  # predicate all send a command-less run into the external pipeline; the
  # external-only specs above can never see that side of the flip (#305
  # dogfood).
  it "never takes the external pipeline without a test command" do
    with_fixture do |root|
      engine = Saboteur::Engine.new(Saboteur::Config.new({}, root: root))
      expect(engine).not_to receive(:call_external)
      allow(Saboteur::Engine::Boot).to receive(:new)
        .with(an_instance_of(Saboteur::Config), an_instance_of(Saboteur::Hooks))
        .and_raise("booted the in-process pipeline")
      expect { engine.send(:run_pipeline, nil, 0.0) }.to raise_error("booted the in-process pipeline")
    end
  end

  # The flipped dispatch condition otherwise walks every covering spec
  # through a full in-process boot until the mutant slice times out; the
  # delegation spec fails fast instead (#305 dogfood timeout).
  it "never boots the target when a test command is configured" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true" }, root: root)
      expect(Saboteur::Engine::Boot).not_to receive(:new)
      Saboteur::Engine.new(config).call
    end
  end

  it "admits the preflight with both its own deadline and the run budget deadline" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true", "baseline_timeout" => 7,
                                      "max_duration" => 50 }, root: root)
      engine = Saboteur::Engine.new(config)
      seen = nil
      allow_any_instance_of(Saboteur::Execution::ExternalRunner).to receive(:preflight!)
        .and_wrap_original do |method, **kwargs|
          seen = kwargs
          method.call(**kwargs)
        end
      engine.call
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(seen[:deadline]).to be_within(2).of(now + 7)
      expect(seen[:budget_deadline]).to be_within(2).of(now + 50)
    end
  end

  it "passes the configured whole_file list to the reevaluator" do
    with_fixture do |root|
      config = Saboteur::Config.new({ "test_command" => "true", "reeval" => "nesting",
                                      "whole_file" => ["K#m"] }, root: root)
      expect(Saboteur::Execution::Reevaluator).to receive(:new).with("nesting", whole_file: ["K#m"])
                                                               .and_call_original
      Saboteur::Engine.new(config).call
    end
  end

  it "leaves the real tree untouched" do
    with_fixture do |root|
      before = File.read(File.join(root, "lib", "k.rb"))
      Saboteur::Engine.new(Saboteur::Config.new({ "test_command" => "true" }, root: root)).call
      expect(File.read(File.join(root, "lib", "k.rb"))).to eq(before)
    end
  end
end
