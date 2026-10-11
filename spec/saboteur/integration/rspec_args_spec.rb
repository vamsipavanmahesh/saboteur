# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Integration::RSpec, "#rspec_args" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "spec"))
      FileUtils.touch(File.join(@root, "spec", "a_spec.rb"))
      FileUtils.touch(File.join(@root, "spec", "b_spec.rb"))
      example.run
    end
  end

  def args(**values)
    described_class.new(Saboteur::Config.new(values.transform_keys(&:to_s), root: @root)).rspec_args
  end

  it "adds the default spec path when no path is configured" do
    expect(args(rspec_args: ["--color"])).to eq(["--color", "spec"])
  end

  it "replaces configured spec paths with the explicit tests and keeps the options" do
    expect(args(rspec_args: ["--color", "spec"], tests: ["spec/a_spec.rb", "spec/b_spec.rb"]))
      .to eq(["--color", "spec/a_spec.rb", "spec/b_spec.rb"])
  end

  it "also replaces a spec path written with a line number" do
    expect(args(rspec_args: ["spec/a_spec.rb:3"], tests: ["spec/b_spec.rb"])).to eq(["spec/b_spec.rb"])
  end

  it "leaves rspec_args alone without explicit tests" do
    expect(args(rspec_args: ["spec/a_spec.rb"])).to eq(["spec/a_spec.rb"])
  end
end
