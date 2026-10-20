# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Config, "tree paths and messages" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:outputs) { [".saboteur", ".saboteur/report.json", ".saboteur/report.html"] }

  def config(values = {}) = described_class.new(values, root: @root)

  describe "#ignored_tree_paths" do
    it "lists only the run's output without a BUNDLE_GEMFILE" do
      expect(config.ignored_tree_paths(gemfile: nil)).to eq(outputs)
    end

    it "leaves out the project's own Gemfile, but not one in a subdirectory" do
      expect(config.ignored_tree_paths(gemfile: "Gemfile")).to eq(outputs)
      expect(config.ignored_tree_paths(gemfile: File.join(@root, "Gemfile"))).to eq(outputs)
      expect(config.ignored_tree_paths(gemfile: "sub/Gemfile"))
        .to eq([*outputs, "sub/Gemfile", "sub/Gemfile.lock"])
    end

    it "accepts an absolute sidecar inside the root and refuses one outside it" do
      expect(config.ignored_tree_paths(gemfile: File.join(@root, "g", "Gemfile.x")))
        .to eq([*outputs, "g/Gemfile.x", "g/Gemfile.x.lock"])
      Dir.mktmpdir do |other|
        expect(config.ignored_tree_paths(gemfile: File.join(File.realpath(other), "Gemfile"))).to eq(outputs)
      end
    end

    it "keeps the spelling when the sidecar's directory does not exist" do
      expect(config.ignored_tree_paths(gemfile: "no/such/Gemfile.x"))
        .to eq([*outputs, "no/such/Gemfile.x", "no/such/Gemfile.x.lock"])
    end

    it "resolves a symlinked directory, so a link out of the root is refused and a link within it is named" do
      FileUtils.mkdir_p(File.join(@root, "real"))
      File.symlink(File.join(@root, "real"), File.join(@root, "inside"))
      Dir.mktmpdir do |other|
        File.symlink(File.realpath(other), File.join(@root, "outside"))

        expect(config.ignored_tree_paths(gemfile: "inside/Gemfile.x"))
          .to eq([*outputs, "real/Gemfile.x", "real/Gemfile.x.lock"])
        expect(config.ignored_tree_paths(gemfile: "outside/Gemfile.x")).to eq(outputs)
      end
    end
  end

  it "names every unknown config key, comma separated" do
    expect { config("nope" => 1, "nada" => 2) }
      .to raise_error(Saboteur::ConfigError, "unknown config key(s): nope, nada")
  end

  it "refuses max_mutants_per_method of zero, with the reason" do
    expect { config("max_mutants_per_method" => 0) }
      .to raise_error(Saboteur::ConfigError, "max_mutants_per_method must be > 0")
  end

  it "lists the reeval strategies when one is refused" do
    expect { config("reeval" => "sometimes") }.to raise_error(
      Saboteur::ConfigError, "reeval must be one of: #{Saboteur::Execution::Reevaluator::STRATEGIES.join(', ')}"
    )
  end

  it "carries the operator policy in the selection settings" do
    settings = config("operators" => ["range"]).selection_settings

    expect(settings["operator_policy"]).to eq(config("operators" => ["range"]).operator_policy)
    expect(settings).to include(config("operators" => ["range"]).to_h)
  end
end
