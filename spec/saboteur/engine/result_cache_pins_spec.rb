# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

# Pins the verdict entry fields, the cache key, the dependency part of the
# fingerprint, the test-file parse and the file digest memo.
RSpec.describe Saboteur::Engine::ResultCache do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "spec"))
      File.write(File.join(@root, "spec", "person_spec.rb"), "# tests\n")
      example.run
    end
  end

  let(:path) { File.join(@root, ".saboteur", "results.json") }
  let(:tests) { ["./spec/person_spec.rb[1:1]"] }
  let(:verdict) do
    result_for(:killed, killed_by: tests, covered_by: tests, kill_cause: "assertion", reason: "boom", runtime: 0.25)
  end

  def cache(**)
    described_class.new(path:, root: @root, inputs: "config-1", **)
  end

  it "returns every stored field of a verdict, with the status as a symbol" do
    store = cache
    store.record(verdict)
    store.save
    expect(cache.lookup(person_subject, comparison_mutation, tests)).to eq(
      status: :killed, reason: "boom", killed_by: tests, kill_cause: "assertion", runtime: 0.25,
      value_differed: nil
    )
  end

  it "writes the status, reason, killing tests, cause and runtime of a verdict to the file" do
    store = cache
    store.record(verdict)
    store.save
    entry = JSON.parse(File.read(path)).fetch("entries").values.first
    expect(entry.except("fingerprint")).to eq("status" => "killed", "reason" => "boom", "killed_by" => tests,
                                              "kill_cause" => "assertion", "runtime" => 0.25,
                                              "value_differed" => nil)
  end

  it "keys an entry by the subject id, a space and the mutation digest" do
    mutation = comparison_mutation
    digest = mutation.digest(subject_start: person_subject.start_byte, original_source: person_subject.file_source)
    expect(cache.send(:key, person_subject, mutation)).to eq("#{person_subject.id} #{digest}")
  end

  it "reads the test file from an example id, a line id, a bare file and an id with no .rb" do
    store = cache
    expect(store.send(:test_file, "./spec/a_spec.rb[1:2]")).to eq(File.join(@root, "spec/a_spec.rb"))
    expect(store.send(:test_file, "./spec/a_spec.rb:12")).to eq(File.join(@root, "spec/a_spec.rb"))
    expect(store.send(:test_file, "./spec/a_spec.rb")).to eq(File.join(@root, "spec/a_spec.rb"))
    expect(store.send(:test_file, "./spec/a.rb_spec.rb[1]")).to eq(File.join(@root, "spec/a.rb_spec.rb"))
    expect(store.send(:test_file, "x\ny_spec.rb[1]")).to eq(File.join(@root, "x\ny_spec.rb[1]"))
    expect(store.send(:test_file, "spec/odd id")).to eq(File.join(@root, "spec/odd id"))
  end

  it "adds each dependency file to the fingerprint as its path, a NUL, its digest and a NUL" do
    helper = File.join(@root, "helper.rb")
    File.write(helper, "CAP = 1\n")
    coverage = Saboteur::Selection::CoverageMap.new(lines: { helper => { 1 => tests } }, tests:)
    store = cache(coverage:)
    plain = Digest::SHA256.new
    store.send(:digest_tests, plain, tests)
    expected = Digest::SHA256.new
    expected << tests.first << "\0" << Digest::SHA256.file(File.join(@root, "spec/person_spec.rb")).hexdigest << "\0"
    expected << helper << "\0" << Digest::SHA256.file(helper).hexdigest << "\0"
    Saboteur::Engine::ResultCache::LOCKFILES.each { |_name| expected << "missing" << "\0" }
    expect(plain.hexdigest).to eq(expected.hexdigest)
  end

  it "digests each file once, a missing file too" do
    present = File.join(@root, "spec/person_spec.rb")
    store = cache
    expect(Digest::SHA256).to receive(:file).with(present).once.and_call_original
    gone = File.join(@root, "gone.rb")
    expect(File).to receive(:file?).with(present).once.and_call_original
    expect(File).to receive(:file?).with(gone).once.and_call_original
    2.times { store.send(:file_digest, present) }
    2.times { expect(store.send(:file_digest, gone)).to eq("missing") }
  end
end
