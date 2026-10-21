# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Pins for the RUBYOPT scrub in ExternalRunner#child_env: the child must not
# keep the parent's -rbundler/setup (it would anchor to the real tree), but it
# keeps every other option. Bundler is hidden so ENV is read as it stands.
RSpec.describe Saboteur::Execution::ExternalRunner, "child RUBYOPT pins" do
  let(:root) { File.realpath(Dir.mktmpdir("ext-env")) }
  let(:runner) { described_class.new(command: "true", root: root) }

  before { hide_const("Bundler") }

  after do
    runner.close
    FileUtils.remove_entry(root)
  end

  def child_rubyopt(value)
    previous = ENV.fetch("RUBYOPT", nil)
    value.nil? ? ENV.delete("RUBYOPT") : ENV["RUBYOPT"] = value
    runner.send(:child_env).fetch("RUBYOPT", :absent)
  ensure
    previous.nil? ? ENV.delete("RUBYOPT") : ENV["RUBYOPT"] = previous
  end

  it "leaves a child with no RUBYOPT without one" do
    expect(child_rubyopt(nil)).to eq(:absent)
  end

  it "drops a RUBYOPT that held only the bundler preload, rather than leaving it empty" do
    expect(child_rubyopt("-rbundler/setup")).to eq(:absent)
  end

  it "keeps the other options and removes the preload with its leading space" do
    expect(child_rubyopt("-w -rbundler/setup")).to eq("-w")
    expect(child_rubyopt("-rbundler/setup -w")).to eq("-w")
    expect(child_rubyopt("-w -rbundler/setup -W0")).to eq("-w -W0")
  end

  it "removes the preload however much space leads it, and strips the ends" do
    expect(child_rubyopt("-w    -rbundler/setup")).to eq("-w")
    expect(child_rubyopt("  -w  ")).to eq("-w")
  end

  it "passes RUBYOPT through untouched when it has no preload" do
    expect(child_rubyopt("-w -W0")).to eq("-w -W0")
  end

  it "marks the child, so a nested run knows it is inside one" do
    expect(runner.send(:child_env)).to include("SABOTEUR_EXTERNAL_CHILD" => "1")
  end
end
