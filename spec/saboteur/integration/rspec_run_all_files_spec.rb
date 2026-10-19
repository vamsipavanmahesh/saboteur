# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"
require "tmpdir"

# run_all(files:) limits a coverage build to the groups the given spec files
# define, so a partitioned build (#741) runs each file in exactly one child.
RSpec.describe Saboteur::Integration::RSpec, "#run_all with files" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      Dir.chdir(@root) { example.run }
    end
  end

  let(:integration) { described_class.new(Saboteur::Config.new({}, root: @root)) }
  let(:recorder) { instance_double(Saboteur::Selection::Recorder) }

  def spec_file(name)
    FileUtils.mkdir_p("spec")
    File.write("spec/#{name}", "# x\n")
    "spec/#{name}"
  end

  def group(file, examples: 1)
    instance_double(RSpec::Core::ExampleGroup.singleton_class, metadata: { file_path: "./#{file}" },
                                                               descendant_filtered_examples: Array.new(examples, 1))
  end

  before do
    first_file = spec_file("a_spec.rb")
    second_file = spec_file("b_spec.rb")
    third_file = spec_file("c_spec.rb")
    @first = group(first_file)
    @second = group(second_file)
    world = instance_double(RSpec::Core::World,
                            ordered_example_groups: [@first, @second, group(third_file, examples: 0)])
    allow(integration).to receive(:world).and_return(world)
  end

  def runnable(files)
    integration.send(:runnable_groups, files)
  end

  it "keeps every group with examples when no files are given" do
    expect(runnable(nil)).to eq([@first, @second])
  end

  it "keeps only the groups defined in the given files, in the world's order" do
    expect(runnable(["spec/b_spec.rb"])).to eq([@second])
    expect(runnable(["spec/b_spec.rb", File.join(@root, "spec/a_spec.rb")])).to eq([@first, @second])
  end

  it "compares real paths, so a symlinked directory names the same file" do
    File.symlink("spec", "linked")

    expect(runnable(["linked/a_spec.rb"])).to eq([@first])
  end

  it "refuses an empty file list instead of running no group" do
    expect { runnable([]) }.to raise_error(ArgumentError, "files must name at least one spec file")
  end

  it "refuses a listed file that defines no runnable group" do
    expect { runnable(["spec/c_spec.rb"]) }
      .to raise_error(ArgumentError, "no example group in: #{File.join(@root, 'spec/c_spec.rb')}")
  end

  it "names every unmatched file, sorted, in one message" do
    spec_file("d_spec.rb")
    allow(integration.send(:world)).to receive(:ordered_example_groups).and_return([@first])

    expect { runnable(["spec/d_spec.rb", "spec/b_spec.rb", "spec/a_spec.rb"]) }
      .to raise_error(ArgumentError, "no example group in: #{File.join(@root, 'spec/b_spec.rb')}, " \
                                     "#{File.join(@root, 'spec/d_spec.rb')}")
  end

  it "refuses a listed file that does not exist" do
    expect { runnable(["spec/nope_spec.rb"]) }.to raise_error(Errno::ENOENT)
  end

  it "counts the examples of the runnable groups for the given files" do
    expect(integration.send(:world)).to receive(:example_count).with([@second]).and_return(7)

    expect(integration.example_count(files: ["spec/b_spec.rb"])).to eq(7)
  end

  it "counts the examples of every runnable group when no files are given" do
    expect(integration.send(:world)).to receive(:example_count).with([@first, @second]).and_return(9)

    expect(integration.example_count).to eq(9)
  end

  it "hands its files to the suite run" do
    allow(integration).to receive(:configuration)
      .and_return(instance_double(RSpec::Core::Configuration, "order=": nil, "fail_fast=": nil))
    expect(integration).to receive(:execute)
      .with(anything, log_phase: true, files: %w[spec/a_spec.rb]).and_return(true)

    expect(integration.run_all(recorder, files: %w[spec/a_spec.rb])).to be(true)
  end
end
