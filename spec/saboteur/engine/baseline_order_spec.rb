# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "baseline refusal" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

  it "stops before coverage lookup, candidate generation and worker preparation" do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    Dir.mktmpdir do |root|
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
      rails = instance_double(Saboteur::Frameworks::Rails)
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      subject_under_test = subjects_in("class Target\n  def m\n    1\n  end\nend\n").first
      selection = instance_double(Saboteur::Engine::SubjectSelection,
                                  select: [subject_under_test], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      baseline = instance_double(Saboteur::Engine::BaselineGuard)
      allow(baseline).to receive(:call).and_raise(Saboteur::Error, "baseline failed")
      expect(Saboteur::Engine::BaselineGuard).to receive(:new) do |config:, integration:, hooks:, supervisor:,
                                                                                diagnostics:, full_passes:|
        expect(full_passes).to eq(3)
        expect(config["seed"]).to eq(1)
        expect(integration).to equal(boot.load_target)
        expect(hooks).to be_a(Saboteur::Hooks)
        expect(supervisor).to be_a(Saboteur::Execution::Supervisor)
        expect(supervisor.instance_variable_get(:@limits).max_memory_mb).to eq(8192)
        expect(diagnostics).to be_a(Saboteur::Engine::Diagnostics)
        baseline
      end
      store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
      expect(store).not_to receive(:fetch)
      expect(Saboteur::Engine::Candidates).not_to receive(:new)
      expect(Saboteur::Engine::ResultCache).not_to receive(:new)
      expect(Saboteur::Engine::Distribution).not_to receive(:new)
      expect(rails).not_to receive(:prepare_workers)
      # The baseline failure still reaches the Engine.call boundary, which
      # releases whatever the boot already snapshotted.
      expect(rails).to receive(:cleanup_workers)
      engine = described_class.new(Saboteur::Config.new({ "incremental" => true }, root: root), err: StringIO.new)
      expect { engine.call }.to raise_error(Saboteur::Error, "baseline failed")
    end
  end
end
