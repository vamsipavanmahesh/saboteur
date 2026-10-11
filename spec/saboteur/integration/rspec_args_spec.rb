# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"

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

  it "makes the explicit tests part of the coverage-map and verdict inputs" do
    expect(Saboteur::Engine::CoverageStore::CACHE_INPUTS).to include("tests")
    expect(Saboteur::Engine::VERDICT_INPUTS).to include("tests")
  end
end
