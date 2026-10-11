# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "baseline refusal" do
  it "stops before coverage lookup, candidate generation and worker preparation" do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    Dir.mktmpdir do |root|
      integration = instance_double(Saboteur::Integration::RSpec)
      rails = instance_double(Saboteur::Frameworks::Rails)
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      subject_under_test = subjects_in("class Target\n  def m\n    1\n  end\nend\n").first
      selection = instance_double(Saboteur::Engine::SubjectSelection,
                                  select: [subject_under_test], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      baseline = instance_double(Saboteur::Engine::BaselineGuard)
      allow(baseline).to receive(:call).and_raise(Saboteur::Error, "baseline failed")
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
      expect(Saboteur::Engine::CoverageStore).not_to receive(:new)
      expect(Saboteur::Engine::Candidates).not_to receive(:new)
      expect(Saboteur::Engine::ResultCache).not_to receive(:new)
      expect(Saboteur::Engine::Distribution).not_to receive(:new)
      expect(rails).not_to receive(:prepare_workers)
      engine = described_class.new(Saboteur::Config.new({ "incremental" => true }, root: root), err: StringIO.new)
      expect { engine.call }.to raise_error(Saboteur::Error, "baseline failed")
    end
  end
end
