# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Custom map problems must reach the report as warnings, or a stale map
# rots silently between the runs where doctor catches it.
RSpec.describe Saboteur::Engine, "custom map warnings" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

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
      allow(Saboteur::CustomMap).to receive(:load).with(File.join(root, "config", "saboteur_custom_map.rb"),
                                                        root: root).and_return(map)
      path = File.join(root, "config", "saboteur_custom_map.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "SABOTEUR_CUSTOM_MAP = {}\n")
      report = described_class.new(Saboteur::Config.new({}, root: root), err: StringIO.new).call
      expect(report.warnings).to include("stale custom map key app/models/gone.rb: matches no file",
                                         "duplicate custom map key app/models/dup.rb: Ruby keeps the last")
    end
  end

  # A config that disables the map (c.custom_map = nil) makes config.path
  # return nil; the duplicate-key check must skip instead of crashing.
  it "skips the duplicate check when the map is disabled" do
    Dir.mktmpdir do |root|
      engine = described_class.new(Saboteur::Config.new({ "custom_map" => nil }, root: root), err: StringIO.new)
      map = instance_double(Saboteur::CustomMap, stale_keys: [])
      expect(map).not_to receive(:duplicate_keys)
      expect(engine.custom_map_warnings(map)).to eq([])
    end
  end

  # Replay never loads the map, but warnings still ask for the path: with the
  # map disabled that path is nil and must not crash a replay either.
  it "skips the duplicate check on a replay with the map disabled" do
    Dir.mktmpdir do |root|
      expect(Saboteur::CustomMap).not_to receive(:load)
      engine = described_class.new(Saboteur::Config.new({ "custom_map" => nil }, root: root),
                                   err: StringIO.new, digest: "deadbeefdeadbeef")
      expect(engine.custom_map_warnings(engine.send(:load_custom_map))).to eq([])
    end
  end
end
