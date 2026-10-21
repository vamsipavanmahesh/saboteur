# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Leftover Engine pins: the no-change guard of #select_subject_tests, the
# scope and the return shape of #replay_subject, and the stale-log cleanup
# of #fresh_log_dir.
RSpec.describe Saboteur::Engine, "#select_subject_tests no-change guard" do
  it "does nothing when no file in scope changed" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    allow(Saboteur::Engine::SubjectSelection).to receive(:files_matching).and_return([])
    guess = instance_double(Saboteur::Engine::TestGuess::Result, changed: 0)
    test_guess = instance_double(Saboteur::Engine::TestGuess, call_for: guess)
    allow(engine).to receive(:test_guess).and_return(test_guess)
    allow(engine).to receive(:inform_skipped_specs)

    engine.send(:select_subject_tests, ["*.rb"])

    expect(engine).not_to have_received(:inform_skipped_specs)
  end
end

RSpec.describe Saboteur::Engine, "#replay_subject pins" do
  it "selects with the given scope and returns the subject alone with no scope" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new, digest: "0123456789abcdef")
    replay = instance_double(Saboteur::Replay)
    engine.instance_variable_set(:@replay, replay)
    allow(Saboteur::Engine::Candidates).to receive(:build).and_return(:candidates)
    scope = Object.new
    expect(replay).to receive(:select).with([:subject], :candidates, scope: scope).and_return(%i[picked candidate])

    expect(engine.send(:replay_subject, [:subject], scope)).to eq([[:picked], nil])
    expect(engine.instance_variable_get(:@replay_candidate)).to eq([:candidate])
  end
end

RSpec.describe Saboteur::Engine, "#fresh_log_dir pins" do
  around do |example|
    Dir.mktmpdir { |dir| @root = File.realpath(dir) and example.run }
  end

  it "removes the stale logs of the last run and recreates the directory" do
    config = Saboteur::Config.new({ "cache_dir" => "cache" }, root: @root)
    engine = described_class.new(config, err: StringIO.new)
    stale_dir = File.join(@root, "cache", "logs")
    FileUtils.mkdir_p(stale_dir)
    File.write(File.join(stale_dir, "stale.log"), "old\n")

    dir = engine.send(:fresh_log_dir)

    expect(dir).to eq(stale_dir)
    expect(Dir.children(dir)).to eq([])
  end
end
