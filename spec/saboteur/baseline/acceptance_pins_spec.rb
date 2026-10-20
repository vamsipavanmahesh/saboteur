# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/acceptance"
require "saboteur/baseline/identity"

# Pins the error messages and guards of Acceptance against mutation survivors.
RSpec.describe Saboteur::Baseline::Acceptance do
  around do |example|
    Dir.mktmpdir do |root|
      @root = File.realpath(root)
      @directory = File.join(@root, ".saboteur", "baseline-evidence")
      @output = File.join(@root, "baseline.json")
      @proposal = File.join(@root, "proposal.json")
      example.run
    end
  end

  let(:identity) do
    Saboteur::Baseline::Identity.new(subject: person_subject, mutation: comparison_mutation,
                                     root: File.dirname(person_subject.file))
  end
  let(:document) do
    { "format" => 1, "identity_version" => 1,
      "metadata" => { "generator" => { "version" => "v1" }, "runtime" => { "version" => "ruby" },
                      "config" => { "seed" => 1 }, "scope" => { "project" => true }, "snapshot" => { "id" => "s" },
                      "subjects" => [["person.rb", "Person#adult?"]], "complete" => true, "issues" => [] },
      "candidates" => [identity.entry.merge("status" => "survived", "kill_cause" => nil)],
      "accepted" => [{ "id" => identity.id, "context" => identity.context, "reason" => "" }] }
  end

  def store(protected_paths: [], directory: @directory)
    described_class.new(directory:, protected_paths:, verify: ->(_) { true })
  end

  def propose(acceptance = store)
    acceptance.propose(document:, proposal: @proposal, destination: @output)
  end

  it "canonicalizes each protected path when it is created" do
    odd = File.join(@root, "sub", "..", "input.json")
    expect(store(protected_paths: [odd]).instance_variable_get(:@protected))
      .to eq([Saboteur::Baseline::Identity.canonical_path(odd)])
  end

  it "wraps a filesystem failure while proposing in the proposal message" do
    File.write(File.join(@root, ".saboteur"), "a file where the directory parent should be")
    expect { propose }.to raise_error(Saboteur::ConfigError, /\Abaseline proposal: /)
  end

  it "refuses a symlinked proposal, destination or evidence directory, naming the path" do
    target = File.join(@root, "target")
    FileUtils.mkdir_p(target)
    File.write(File.join(@root, "real.json"), "{}")
    File.symlink(File.join(@root, "real.json"), @proposal)
    expect { propose }.to raise_error(Saboteur::ConfigError, "baseline symlink path: #{@proposal}")
    File.delete(@proposal)
    File.symlink(File.join(@root, "real.json"), @output)
    expect { propose }.to raise_error(Saboteur::ConfigError, "baseline symlink path: #{@output}")
    File.delete(@output)
    File.symlink(target, File.join(@root, "evidence-link"))
    expect { propose(store(directory: File.join(@root, "evidence-link"))) }
      .to raise_error(Saboteur::ConfigError, "baseline symlink path: #{File.join(@root, 'evidence-link')}")
  end

  it "refuses a proposal inside the evidence directory but not a sibling that shares its name prefix" do
    inside = File.join(@directory, "p.json")
    expect { store.propose(document:, proposal: inside, destination: @output) }
      .to raise_error(Saboteur::ConfigError, "baseline artifact aliases local evidence directory")
    sibling = File.join("#{@directory}-other", "p.json")
    FileUtils.mkdir_p(File.dirname(sibling))
    expect { store.propose(document:, proposal: sibling, destination: @output) }.not_to raise_error
  end

  it "names the path of a destination that aliases a protected input" do
    expect { propose(store(protected_paths: [@proposal])) }
      .to raise_error(Saboteur::ConfigError, "baseline artifact aliases an input: #{@proposal}")
  end

  it "accepts only a lowercase 32-character hex token, whole string" do
    acceptance = store
    ok = "a1" * 16
    expect(acceptance.send(:evidence_path, ok)).to eq(File.join(@directory, "#{ok}.json"))
    ["z" * 32, "#{ok}x", "x#{ok}", "#{ok}\nx", "x\n#{ok}", ok.upcase, ok[0, 31], 5, nil].each do |bad|
      expect { acceptance.send(:evidence_path, bad) }
        .to raise_error(Saboteur::ConfigError, "baseline evidence token"), bad.inspect
    end
  end

  it "reports malformed record JSON with the parser's message" do
    File.write(@proposal, "{nope")
    expect { store.send(:read_record, @proposal) }
      .to raise_error(Saboteur::ConfigError, /\Abaseline evidence JSON: .+/)
  end

  it "rejects an accepted list with any non-hash entry, not only an all-bad one" do
    expect { store.send(:validate_nested_document, { "accepted" => [{}, 1] }) }
      .to raise_error(Saboteur::ConfigError, "baseline proposal document or acceptance shape")
    expect(store.send(:validate_nested_document, { "accepted" => [{}, {}] })).to be_nil
  end

  it "says which output exists when the proposal file is already there" do
    File.write(@proposal, "taken")
    expect { propose }.to raise_error(Saboteur::ConfigError, "baseline output exists: #{@proposal}")
  end

  it "reports a destination that appears between the check and the initial link" do
    acceptance = store
    propose(acceptance)
    edit = JSON.parse(File.read(@proposal))
    edit["document"]["accepted"][0]["reason"] = "reviewed"
    File.write(@proposal, JSON.generate(edit))
    allow(File).to receive(:link).and_raise(Errno::EEXIST)
    expect { acceptance.accept(proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, "baseline destination exists")
  end
end
