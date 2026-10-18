# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "generation evidence" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  it "carries typed generation, omission and diff evidence through the full call" do
    Dir.mktmpdir do |root|
      subject = subjects_in("class EvidenceProbe; def value; 1; end; end").first
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject],
                                                                      behavior_lines: { subject.file => Set[1] })
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      scope = instance_double(Saboteur::Engine::DiffScope)
      allow(Saboteur::Engine::DiffScope).to receive(:new).and_return(scope)
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      allow(Saboteur::Engine::Diagnostics).to receive(:new).and_return(diagnostics)
      engine = described_class.new(Saboteur::Config.new({}, root: root), err: StringIO.new)
      allow(engine).to receive(:mutate) do
        diagnostics.record_generation(subject, source: "custom", operator: "bad", reason: "invalid_syntax")
        diagnostics.record_omission(subject, count: 3, limit: 2)
        []
      end

      report = engine.call

      expected_event = { file: subject.file, subject: "EvidenceProbe#value", source: "custom",
                         operator: "bad", reason: "invalid_syntax" }
      expect(report.generation_events.map(&:to_h)).to eq([expected_event])
      expect(report.omissions.map(&:to_h)).to eq([{ subject: "EvidenceProbe#value", count: 3, limit: 2 }])
      expect(report.omissions).to be_frozen
      expect { report.omissions << :changed }.to raise_error(FrozenError)
      result = instance_double(Saboteur::MutantResult, subject: subject, mutation: :mutation)
      expect(scope).to receive(:changed_lines_for).with(subject, :mutation).and_return([1])
      expect(report.changed_lines_for(result)).to eq([1])
    end
  end
end
