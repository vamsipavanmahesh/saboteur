# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::CoverageStore, "recorder choice (#725)" do
  def store(**settings)
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: root)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      yield described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: nil, diagnostics: nil)
    end
  end

  it "records with the Coverage recorder by default" do
    store { |built| expect(built.send(:recorder_class)).to be(Saboteur::Selection::Recorder) }
  end

  it "records with the TracePoint recorder when asked" do
    store(coverage_recorder: "trace") { |built| expect(built.send(:recorder_class)).to be(Saboteur::Selection::TraceRecorder) }
  end

  it "keeps maps from the two recorders apart in the cache key" do
    keys = %w[coverage trace].map { |name| store(coverage_recorder: name) { |built| built.send(:key_inputs) } }
    expect(keys.uniq.size).to eq(2)
  end
end
