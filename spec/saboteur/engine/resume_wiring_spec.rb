# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "--resume wiring (#471)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      File.write(File.join(@root, "Gemfile.lock"), "lock\n")
      example.run
    end
  end

  # A saboteur child (a dogfood run) refuses to start another engine.
  before { allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!) }

  def engine_with(values, **kwargs)
    config = Saboteur::Config.new(values, root: @root)
    described_class.new(config, err: StringIO.new, **kwargs)
  end

  def plant_bad_manifest
    FileUtils.mkdir_p(File.join(@root, "state"))
    File.write(File.join(@root, "state", "manifest.json"), "{nope")
  end

  describe "#call" do
    it "fails with a ConfigError on a mismatched manifest before any test selection or coverage build" do
      plant_bad_manifest
      engine = engine_with({ "resume" => "state" })
      allow(engine).to receive(:select_tests)
      expect { engine.call }.to raise_error(Saboteur::ConfigError, /unreadable manifest/)
      expect(engine).not_to have_received(:select_tests)
    end

    it "leaves the filesystem alone in preflight without a resume directory" do
      expect { engine_with({}).send(:preflight!) }.not_to raise_error
      expect(Dir.children(@root)).to eq(["Gemfile.lock"])
    end

    it "creates the manifest in preflight for a fresh resume directory" do
      engine = engine_with({ "resume" => "state" })
      engine.send(:preflight!)
      expect(File).to exist(File.join(@root, "state", "manifest.json"))
    end
  end

  describe "baseline evidence" do
    it "refuses a resume directory like the other reuse settings" do
      expect { engine_with({ "resume" => "state" }, capture_evidence: true) }
        .to raise_error(Saboteur::ConfigError, /baseline evidence requires fresh whole-scope execution/)
    end
  end

  describe "#result_cache" do
    def results_files
      Dir.glob(File.join(@root, "**", "results.json")).map { |file| file.delete_prefix("#{@root}/") }
    end

    it "keeps verdicts in the resume directory and not in cache_dir" do
      engine_with({ "resume" => "state", "cache_dir" => "cache" }).send(:result_cache).save
      expect(results_files).to eq(["state/results.json"])
    end

    it "keeps verdicts in cache_dir for --incremental alone" do
      engine_with({ "incremental" => true, "cache_dir" => "cache" }).send(:result_cache).save
      expect(results_files).to eq(["cache/results.json"])
    end

    it "keeps no verdicts without either setting" do
      expect(engine_with({}).send(:result_cache)).to be_nil
    end
  end
end
