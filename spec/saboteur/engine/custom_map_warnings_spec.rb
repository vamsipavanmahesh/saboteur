# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Custom map problems must reach the report as warnings, or a stale map
# rots silently between the runs where doctor catches it.
RSpec.describe Saboteur::Engine, "custom map warnings" do
  it "carries stale and duplicate map keys into the report" do
    Dir.mktmpdir do |root|
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      map = instance_double(Saboteur::CustomMap,
                            stale_keys: ["app/models/gone.rb"],
                            duplicate_keys: ["app/models/dup.rb"])
      allow(Saboteur::CustomMap).to receive(:load).and_return(map)
      path = File.join(root, "config", "saboteur_custom_map.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "SABOTEUR_CUSTOM_MAP = {}\n")
      report = described_class.new(Saboteur::Config.new({}, root: root), err: StringIO.new).call
      expect(report.warnings).to include("stale custom map key app/models/gone.rb: matches no file",
                                         "duplicate custom map key app/models/dup.rb: Ruby keeps the last")
    end
  end
end
