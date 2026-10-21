# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins for Engine#select_subjects: unmatched patterns warn verbatim, the
# selection sees the given test files and the loaded custom map, and a diff
# scope is built from the behavior lines.
RSpec.describe Saboteur::Engine, "select_subjects pins" do
  let(:config) { Saboteur::Config.new({}) }
  let(:engine) { described_class.new(config, err: StringIO.new) }
  let(:diagnostics) { engine.instance_variable_get(:@diagnostics) }
  let(:selection) { double("selection", select: [:subject], behavior_lines: nil) }

  before do
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  it "warns once per unmatched pattern, naming it" do
    allow(config).to receive(:unmatched_patterns).and_return(["nope.rb", "gone/*.rb"])
    engine.send(:select_subjects, ["lib/a.rb"])
    expect(diagnostics.warnings).to eq(["nope.rb matches no file", "gone/*.rb matches no file"])
  end

  it "hands the test files and the loaded custom map to the selection" do
    map = engine.send(:load_custom_map)
    engine.send(:select_subjects, ["lib/a.rb"], test_files: ["spec/a_spec.rb"])
    expect(Saboteur::Engine::SubjectSelection).to have_received(:new)
      .with(config, diagnostics, test_files: ["spec/a_spec.rb"], custom_map: map)
  end

  it "builds the diff scope from the behavior lines" do
    lines = { "lib/a.rb" => [3, 4] }
    scoped = double("selection", select: [:subject], behavior_lines: lines)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(scoped)
    allow(Saboteur::Engine::DiffScope).to receive(:new).and_return(:scope)
    subjects, scope = engine.send(:select_subjects, ["lib/a.rb"])
    expect(Saboteur::Engine::DiffScope).to have_received(:new).with(lines)
    expect([subjects, scope]).to eq([[:subject], :scope])
  end

  it "leaves the scope nil without behavior lines" do
    _subjects, scope = engine.send(:select_subjects, ["lib/a.rb"])
    expect(scope).to be_nil
  end
end
