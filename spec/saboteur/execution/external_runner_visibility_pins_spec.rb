# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Pins for the mutation visibility check of ExternalRunner: only a failing,
# runnable test command proves the command loads the mutated copy, and the
# check mutation must replace the whole file with a load-time error.
RSpec.describe Saboteur::Execution::ExternalRunner, "visibility pins" do
  let(:root) { File.realpath(Dir.mktmpdir("ext-vis")) }
  let(:runner) { described_class.new(command: "true", root: root) }
  let(:file) { File.join(root, "thing.rb") }
  let(:subject_double) { double("subject", file: file, id: "Thing#call", file_source: "def call\n  1\nend\n") }

  before { File.write(file, subject_double.file_source) }

  after do
    runner.close
    FileUtils.remove_entry(root)
  end

  describe "#visibility_warning" do
    it "stays silent only when the command failed in the test, not in setup" do
      expect(runner.send(:visibility_warning, subject_double, 1)).to be_nil
      expect(runner.send(:visibility_warning, subject_double, 42)).to be_nil
    end

    it "warns when the suite still passed with the file replaced by a load error" do
      warning = runner.send(:visibility_warning, subject_double, 0)
      expect(warning).to include("mutation visibility check failed for thing.rb")
      expect(warning).to include("the test command still passed")
    end

    it "warns when the command timed out" do
      expect(runner.send(:visibility_warning, subject_double, :timeout)).to include("the test command timed out")
    end

    it "warns when the command died to a signal or never ran" do
      expect(runner.send(:visibility_warning, subject_double, :signal)).to include("could not run (killed by a signal)")
      expect(runner.send(:visibility_warning, subject_double,
                         126)).to include("could not run (exit 126 - the shell could not run the command)")
      expect(runner.send(:visibility_warning, subject_double,
                         127)).to include("could not run (exit 127 - the shell could not run the command)")
    end

    it "warns with the exception message when the command could not start" do
      warning = runner.send(:visibility_warning, subject_double, RuntimeError.new("no shell"))
      expect(warning).to include("the test command could not be started: no shell")
    end
  end

  describe "#visibility_mutation" do
    it "replaces the whole file with a load-time error" do
      mutation = runner.send(:visibility_mutation, subject_double)
      expect(mutation.operator).to eq("visibility_check")
      expect(mutation.subject_id).to eq("Thing#call")
      expect(mutation.edits.size).to eq(1)
      edit = mutation.edits.first
      expect(edit.file).to eq(file)
      expect(edit.start_byte).to eq(0)
      expect(edit.end_byte).to eq(subject_double.file_source.bytesize)
      expect(edit.replacement).to include("must not load during the check")
      expect(edit.replacement).to start_with("raise ")
    end

    it "is a fine-grained mutation, so the check runs where the subject runs" do
      expect(runner.send(:visibility_mutation, subject_double).coarse).to be(false)
    end
  end
end
