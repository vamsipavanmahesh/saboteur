# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::MutationSource::ElementRemoval do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def constant_subject(text)
    file = File.join(@root, "constants.rb")
    File.write(file, text)
    Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
  end

  def texts(text)
    subject = constant_subject(text)
    described_class.new.mutations_for(subject, root: subject.literal_node).map do |mutation|
      subject.apply(mutation.edits)
    end
  end

  it "removes one element at a time, keeping the array parseable" do
    expect(texts("LIST = [1, 2, 3]\n")).to eq(["LIST = [ 2, 3]", "LIST = [1,  3]", "LIST = [1, 2 ]"])
  end

  it "removes the sole element" do
    expect(texts("LIST = [1]\n")).to eq(["LIST = []"])
  end

  it "removes whitespace-separated %w elements" do
    expect(texts("LIST = %w[a b]\n")).to eq(["LIST = %w[ b]", "LIST = %w[a ]"])
  end

  it "proposes nothing for an empty array" do
    expect(texts("LIST = []\n")).to be_empty
  end

  it "descends into nested arrays but not into methods" do
    texts = texts("LIST = [[1, 2], [3]]\n")
    expect(texts).to include("LIST = [ [3]]", "LIST = [[1, 2] ]", "LIST = [[ 2], [3]]", "LIST = [[1 ], [3]]",
                             "LIST = [[1, 2], []]")
    expect(texts.size).to eq(5)
  end

  it "leaves elements holding a heredoc alone" do
    # The heredoc body lives on later lines, outside the assignment's span.
    expect(texts("LIST = [<<~A, 2]\n  text\nA\n")).to eq(["LIST = [<<~A ]"])
  end

  it "leaves splat elements intact" do
    expect(texts("LIST = [*A, 2]\n")).to eq(["LIST = [*A ]"])
  end

  it "names the operator and source element_removal" do
    subject = constant_subject("LIST = [1, 2]\n")
    mutation = described_class.new.mutations_for(subject, root: subject.literal_node).first
    expect([mutation.operator, mutation.source, mutation.coarse]).to eq(["element_removal", "element_removal", false])
    expect(mutation.subject_id).to eq("LIST")
  end
end
