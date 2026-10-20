# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::Canary, "pins" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def touch(relative)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    path
  end

  def full_message(count, first, culprit)
    "canary: #{count} watched file(s) vanished from the working tree while mutants ran (first: #{first})." \
      "#{culprit} The canary watches tracked files and .git presence and only detects the loss after the fact; " \
      "it cannot restore anything. Recover from your own backup, a fresh checkout, or a reclone - a deleted .git " \
      "or uncommitted work is gone unless you have another copy."
  end

  let(:subject_id) { Struct.new(:id).new("K#m") }

  it "names the first vanished file, the count and the most recent mutant in check!" do
    a = touch("a.txt")
    b = touch("b.txt")
    canary = described_class.new(@root)
    File.delete(a, b)
    expect { canary.check!(subject: subject_id, digest: "abcd") }.to raise_error(
      Saboteur::CanaryTripped,
      full_message(2, "a.txt", " The most recent mutant, abcd of K#m, is the likely cause.")
    )
  end

  it "leaves the culprit out of check! when no digest is known" do
    a = touch("a.txt")
    canary = described_class.new(@root)
    File.delete(a)
    expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, full_message(1, "a.txt", ""))
  end

  it "names the mutant that just ran in probe!, and carries its digest" do
    a = touch("a.txt")
    canary = described_class.new(@root)
    File.delete(a)
    expect { canary.probe!(subject: subject_id, digest: "abcd") }.to raise_error(Saboteur::CanaryTripped) do |error|
      culprit = " The mutant that just ran, abcd of K#m, is the likely cause."
      expect(error.message).to eq(full_message(1, "a.txt", culprit))
      expect(error.culprit_digest).to eq("abcd")
    end
  end

  it "watches files, not directories, and skips only the cache dir and .git contents" do
    touch("keep/a.txt")
    touch(".gitignore")
    touch(".github/w.yml")
    touch(".saboteur/log.txt")
    touch(".saboteurx/y.txt")
    FileUtils.mkdir_p(File.join(@root, "emptydir"))
    canary = described_class.new(@root)
    FileUtils.rm_rf(File.join(@root, "emptydir"))
    FileUtils.rm_rf(File.join(@root, ".saboteur"))
    expect(canary.probe).to eq([])
    FileUtils.rm_rf(File.join(@root, ".saboteurx"))
    File.delete(File.join(@root, ".gitignore"))
    expect(canary.probe).to eq([".gitignore", ".saboteurx/y.txt"])
  end
end
