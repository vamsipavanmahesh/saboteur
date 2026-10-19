# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"

# run_all(files:) limits a coverage build to the groups the given spec files
# define, so a partitioned build (#741) runs each file in exactly one child.
RSpec.describe Saboteur::Integration::RSpec, "#run_all with files" do
  let(:integration) { described_class.new(Saboteur::Config.new({}, root: Dir.pwd)) }
  let(:recorder) { instance_double(Saboteur::Selection::Recorder) }

  def group(file, examples: 1)
    instance_double(RSpec::Core::ExampleGroup.singleton_class, metadata: { file_path: file },
                                                               descendant_filtered_examples: Array.new(examples, 1))
  end

  let(:first) { group("./spec/a_spec.rb") }
  let(:second) { group("./spec/b_spec.rb") }
  let(:empty) { group("./spec/c_spec.rb", examples: 0) }
  let(:world) { instance_double(RSpec::Core::World, ordered_example_groups: [first, second, empty]) }

  before { allow(integration).to receive(:world).and_return(world) }

  def runnable(files)
    integration.send(:runnable_groups, files)
  end

  it "keeps every group with examples when no files are given" do
    expect(runnable(nil)).to eq([first, second])
  end

  it "keeps only the groups defined in the given files, in the world's order" do
    expect(runnable([File.expand_path("spec/b_spec.rb")])).to eq([second])
    expect(runnable(%w[spec/b_spec.rb spec/a_spec.rb])).to eq([first, second])
  end

  it "keeps nothing for a file that defines no group" do
    expect(runnable(%w[spec/z_spec.rb])).to eq([])
  end

  it "does not run a listed file whose examples are all filtered out" do
    expect(runnable(%w[spec/c_spec.rb])).to eq([])
  end

  it "hands its files to the suite run" do
    allow(integration).to receive(:configuration)
      .and_return(instance_double(RSpec::Core::Configuration, "order=": nil, "fail_fast=": nil))
    expect(integration).to receive(:execute)
      .with(anything, log_phase: true, files: %w[spec/a_spec.rb]).and_return(true)

    expect(integration.run_all(recorder, files: %w[spec/a_spec.rb])).to be(true)
  end
end
