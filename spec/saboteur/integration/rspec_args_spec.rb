# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"
require "tmpdir"

RSpec.describe Saboteur::Integration::RSpec, "#configuration_options" do
  def options(**values)
    config = Saboteur::Config.new(values.transform_keys(&:to_s), root: Dir.pwd)
    described_class.new(config).configuration_options.options
  end

  it "runs the paths in rspec_args when no tests are named" do
    expect(options(rspec_args: ["spec/a_spec.rb"])[:files_or_directories_to_run]).to eq(["spec/a_spec.rb"])
  end

  it "replaces only the files to run, keeping option values such as --require paths" do
    selected = options(rspec_args: ["--require", "spec/spec_helper.rb", "spec"], tests: ["spec/a_spec.rb:3"])
    expect(selected[:files_or_directories_to_run]).to eq(["spec/a_spec.rb:3"])
    expect(selected[:requires]).to include("spec/spec_helper.rb")
  end

  it "defaults to spec when nothing is configured" do
    expect(options[:files_or_directories_to_run]).to eq(["spec"])
  end

  it "adds the default path when rspec_args holds only options and their values" do
    [%w[--require spec_helper], %w[--format documentation], ["--exclude-pattern", "spec/fixtures/**/*_spec.rb"]]
      .each do |args|
      expect(options(rspec_args: args)[:files_or_directories_to_run]).to eq(["spec"]), args.inspect
    end
  end

  it "adds the default path that .rspec sets instead of spec" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".rspec"), "--default-path test\n")
      Dir.chdir(dir) do
        expect(options[:files_or_directories_to_run]).to eq(["test"])
        expect(options(rspec_args: %w[--require helper])[:files_or_directories_to_run]).to eq(["test"])
      end
    end
  end

  it "makes the explicit tests part of the coverage-map and verdict inputs" do
    expect(Saboteur::Engine::CoverageStore::CACHE_INPUTS).to include("tests")
    expect(Saboteur::Engine::VERDICT_INPUTS).to include("tests")
  end
end
