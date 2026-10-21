# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Pins the replay guard of Engine#result_cache and every keyword argument
# it hands to ResultCache.
RSpec.describe Saboteur::Engine, "#result_cache wiring" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      File.write(File.join(@root, "Gemfile.lock"), "lock\n")
      example.run
    end
  end

  before { allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!) }

  def engine_with(values, **kwargs)
    config = Saboteur::Config.new(values, root: @root)
    described_class.new(config, err: StringIO.new, **kwargs)
  end

  let(:cache_values) { { "incremental" => true, "cache_dir" => "cache" } }

  it "returns no cache in replay mode even when reuse settings are on" do
    engine = engine_with(cache_values, digest: "0123456789abcdef")
    expect(engine.send(:result_cache)).to be_nil
  end

  it "hands the suite digest to the cache" do
    engine = engine_with(cache_values)
    cache = engine.send(:result_cache)
    expect(cache.instance_variable_get(:@suite_digest))
      .to eq(Saboteur::Engine::SuiteFiles.new(engine.config).digest)
  end

  it "hands the given coverage map to the cache" do
    engine = engine_with(cache_values)
    map = Object.new
    expect(engine.send(:result_cache, map).instance_variable_get(:@coverage)).to be(map)
  end

  it "hands the source files of the given files to the cache" do
    engine = engine_with(cache_values)
    allow(engine).to receive(:source_files).with(["lib/foo.rb"]).and_return(["lib/foo.rb"])
    cache = engine.send(:result_cache, nil, ["lib/foo.rb"])
    expect(cache.instance_variable_get(:@fallback_files)).to eq([File.join(@root, "lib/foo.rb")])
  end
end
