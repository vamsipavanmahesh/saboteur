# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The --test-command mode takes its own pipeline: no test inference, one
# job, mutants decided by the command's exit status (#140, #305).
RSpec.describe "Engine external test-command pipeline" do
  def with_fixture
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "k.rb"), "class K\n  def m(a)\n    a + 1\n  end\nend\n")
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

  it "leaves the real tree untouched" do
    with_fixture do |root|
      before = File.read(File.join(root, "lib", "k.rb"))
      Saboteur::Engine.new(Saboteur::Config.new({ "test_command" => "true" }, root: root)).call
      expect(File.read(File.join(root, "lib", "k.rb"))).to eq(before)
    end
  end
end
