# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "tmpdir"
require "stringio"

RSpec.describe Saboteur::Engine, "operator policy" do
  it "announces the effective operators when a run starts" do
    # An in-process engine call suspends Coverage after boot; a suite measured
    # by Coverage (the self-dogfood map build) must not inherit the suspension.
    resume_coverage = Coverage.running?
    stub_const("ENV", ENV.to_h.except(Saboteur::Execution::Supervisor::CHILD_ENV))
    Dir.mktmpdir do |dir|
      engine = described_class.new(Saboteur::Config.new({}, root: dir))
      diagnostics = engine.instance_variable_get(:@diagnostics)
      allow(diagnostics).to receive(:detail).and_call_original
      begin
        engine.call
      rescue Saboteur::Error, Saboteur::ConfigError
        # Boot fails in an empty directory; the announcement happens first.
      end
      expect(diagnostics).to have_received(:detail).with(/\AOperators: \w+(, \w+)+/)
    end
  ensure
    Coverage.resume if resume_coverage && Coverage.state == :suspended
  end

  it "binds the operator policy into the result-cache inputs" do
    Dir.mktmpdir do |dir|
      default = described_class.new(Saboteur::Config.new({ "incremental" => true }, root: dir))
      ranged = described_class.new(Saboteur::Config.new({ "incremental" => true, "operators" => ["range"] },
                                                        root: dir))
      inputs = default.send(:result_cache).instance_variable_get(:@inputs)
      expect(inputs).to include('"operator_policy"')
      expect(inputs).not_to eq(ranged.send(:result_cache).instance_variable_get(:@inputs))
    end
  end

  it "carries the policy onto the built report" do
    Dir.mktmpdir do |dir|
      config = Saboteur::Config.new({}, root: dir)
      engine = described_class.new(config)
      report = engine.send(:build_report, [], [], {}, 0.0)
      expect(report.operator_policy).to eq(config.operator_policy)
    end
  end
end
