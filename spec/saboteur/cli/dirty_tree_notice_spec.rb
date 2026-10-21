# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::DirtyTreeNotice do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the dirty tree warning, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(:warn_dirty_tree)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(:warn_dirty_tree)
  end

  # Behavior pins (#841): called here so the dogfood run that selects this
  # spec by name sees the method execute.
  describe "#warn_dirty_tree" do
    let(:err) { StringIO.new }
    let(:config) { instance_double(Saboteur::Config) }

    before { allow(config).to receive(:[]).with("palette").and_return(nil) }

    def cli(argv = [])
      Saboteur::CLI.new(argv, err: err).tap { |run| allow(run).to receive(:config).and_return(config) }
    end

    it "prints the warning for the configured scope" do
      allow(Saboteur::DirtyTreeWarning).to receive(:for).with(config, config_path: nil).and_return("tree is dirty")

      cli.send(:warn_dirty_tree)

      expect(err.string).to eq("tree is dirty\n")
    end

    it "falls back to auto colour detection when no colour mode is set" do
      allow(Saboteur::DirtyTreeWarning).to receive(:for).and_return("tree is dirty")
      allow(Saboteur::Reporter::Palette).to receive(:for).and_call_original

      cli.send(:warn_dirty_tree)

      expect(Saboteur::Reporter::Palette).to have_received(:for).with(err, mode: :auto, overrides: nil)
      expect(err.string).to eq("tree is dirty\n")
    end

    it "paints the notice with the warn token when colour is on" do
      allow(Saboteur::DirtyTreeWarning).to receive(:for).and_return("tree is dirty")
      run = cli
      run.instance_variable_set(:@color, :always)

      run.send(:warn_dirty_tree)

      expect(err.string).to eq("\e[33mtree is dirty\e[0m\n")
    end

    it "honours the config palette override for the warn token" do
      allow(config).to receive(:[]).with("palette").and_return({ "warn" => ["red"] })
      allow(Saboteur::DirtyTreeWarning).to receive(:for).and_return("tree is dirty")
      run = cli
      run.instance_variable_set(:@color, :always)

      run.send(:warn_dirty_tree)

      expect(err.string).to eq("\e[31mtree is dirty\e[0m\n")
    end

    it "prints nothing when the tree is clean" do
      allow(Saboteur::DirtyTreeWarning).to receive(:for).and_return(nil)

      cli.send(:warn_dirty_tree)

      expect(err.string).to eq("")
    end

    it "passes the --config path through" do
      run = cli
      run.send(:options).merge!(config: "ci.rb")
      allow(Saboteur::DirtyTreeWarning).to receive(:for).with(config, config_path: "ci.rb").and_return("w")

      run.send(:warn_dirty_tree)

      expect(err.string).to eq("w\n")
    end

    it "names the configured scope, not the one the source operands imply" do
      configured = instance_double(Saboteur::Config)
      allow(configured).to receive(:[]).with("palette").and_return(nil)
      run = cli(["lib/a.rb"])
      run.send(:options).merge!(include: ["lib/a.rb"], exclude: [], jobs: 2, config: "ci.rb")
      run.instance_variable_set(:@sources, ["lib/a.rb"])
      allow(Saboteur::Config).to receive(:load).and_return(configured)
      allow(Saboteur::DirtyTreeWarning).to receive(:for).with(configured, config_path: "ci.rb").and_return("scoped")

      run.send(:warn_dirty_tree)

      expect(Saboteur::Config).to have_received(:load).with(path: "ci.rb", overrides: { jobs: 2 })
      expect(err.string).to eq("scoped\n")
    end
  end
end
