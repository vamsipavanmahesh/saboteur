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

  describe "required evidence and record shapes" do
    def required_store
      described_class.new(directory: @directory, protected_paths: [], verify: ->(_) { true }, require_evidence: true)
    end

    it "does not demand execution evidence unless asked to" do
      expect { propose }.not_to raise_error
    end

    it "demands execution evidence when asked to, and says it is missing" do
      expect { propose(required_store) }
        .to raise_error(Saboteur::ConfigError, "baseline execution evidence missing")
    end

    it "checks given execution evidence instead of calling it missing when it is demanded" do
      expect { required_store.send(:validate_execution, document, {}) }
        .to raise_error(Saboteur::ConfigError, "baseline evidence fields")
    end

    it "includes the system error in an accept failure and in a proposal failure" do
      acceptance = store
      File.write(File.join(@root, ".saboteur"), "blocker")
      expect { propose(acceptance) }
        .to raise_error(Saboteur::ConfigError, /\Abaseline proposal: .*(Not a directory|File exists)/)
      FileUtils.rm_f(File.join(@root, ".saboteur"))
      acceptance.propose(document:, proposal: @proposal, destination: @output)
      token = JSON.parse(File.read(@proposal))["token"]
      File.delete(File.join(@directory, "#{token}.json"))
      expect { acceptance.accept(proposal: @proposal, destination: @output) }
        .to raise_error(Saboteur::ConfigError, /\Abaseline evidence: .*No such file or directory/)
    end

    it "reads a record with exactly the four keys, or those four plus execution, and nothing else" do
      base = { "destination" => @output, "document" => { "accepted" => [{}] }, "previous" => nil, "token" => "a" * 32 }
      [base, base.merge("execution" => {})].each do |record|
        File.write(@proposal, JSON.generate(record))
        expect(store.send(:read_record, @proposal)).to eq(record)
        record.each_key.reject { |key| key == "execution" }.each do |key|
          File.write(@proposal, JSON.generate(record.except(key)))
          expect { store.send(:read_record, @proposal) }
            .to raise_error(Saboteur::ConfigError, "baseline evidence fields"), key
        end
      end
      File.write(@proposal, JSON.generate(base.merge("extra" => 1)))
      expect { store.send(:read_record, @proposal) }.to raise_error(Saboteur::ConfigError, "baseline evidence fields")
    end
  end
end
