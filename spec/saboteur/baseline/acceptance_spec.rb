# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/acceptance"
require "saboteur/baseline/identity"

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
  let(:store) { described_class.new(directory: @directory, protected_paths: [], verify: ->(_) { true }) }

  def propose(previous: nil)
    store.propose(document: document, proposal: @proposal, destination: @output, previous: previous)
    edit = JSON.parse(File.read(@proposal))
    edit["document"]["accepted"][0]["reason"] = "reviewed known gap"
    File.write(@proposal, JSON.generate(edit))
    edit
  end

  it "rejects distinct public proposal and destination paths that are the same inode" do
    File.write(@proposal, "original")
    File.link(@proposal, @output)
    expect { store.accept(proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /proposal and destination alias/)
    expect(File.read(@output)).to eq("original")
  end

  it "creates the atomic staging file in the destination directory with a private baseline name" do
    propose
    expect(Tempfile).to receive(:create).with([".baseline-", ".json"], @root).and_call_original
    allow(File).to receive(:open).and_call_original
    expect(File).to receive(:open).with(@proposal, File::RDONLY | File::NOFOLLOW).and_call_original
    store.accept(proposal: @proposal, destination: @output)
    expect(File.stat(@output).mode & 0o777).to eq(0o600)
  end

  it "rejects malformed nested editable documents before binding without consuming private evidence" do
    [nil, {}, { "accepted" => nil }, { "accepted" => [nil] }, { "accepted" => [1] }].each do |bad|
      FileUtils.rm_f(@proposal)
      edit = propose
      evidence = File.join(@directory, "#{edit['token']}.json")
      edit["document"] = bad
      File.write(@proposal, JSON.generate(edit))
      expect { store.accept(proposal: @proposal, destination: @output) }
        .to raise_error(Saboteur::ConfigError, /document or acceptance shape/)
      expect(File.exist?(evidence)).to be(true)
      expect(File.exist?(@output)).to be(false)
    end
  end

  it "allows ordinary artifacts under a symlinked checkout parent without allowing a symlink artifact" do
    Dir.mktmpdir do |parent|
      link = File.join(parent, "checkout")
      File.symlink(@root, link)
      alias_store = described_class.new(directory: File.join(link, ".saboteur", "baseline-evidence"),
                                        protected_paths: [], verify: ->(_) { true })
      alias_store.propose(document: document, proposal: File.join(link, "proposal.json"),
                          destination: File.join(link, "baseline.json"))
      edit = JSON.parse(File.read(@proposal))
      edit["document"]["accepted"][0]["reason"] = "reviewed"
      File.write(@proposal, JSON.generate(edit))
      expect(alias_store.accept(proposal: File.join(link, "proposal.json"),
                                destination: File.join(link, "baseline.json"))).to eq(@output)
    end
  end

  it "rejects nested malformed proposal input before generating evidence" do
    expect do
      store.propose(document: { "accepted" => nil }, proposal: @proposal, destination: @output)
    end.to raise_error(Saboteur::ConfigError, /document or acceptance shape/)
    expect(File.exist?(@directory)).to be(false)
  end

  it "refuses a newly introduced symlink ancestor during the pre-write safety check" do
    alias_directory = File.join(@root, "alias")
    File.symlink(@root, alias_directory)
    expect { store.send(:safe_path, File.join(alias_directory, "output.json")) }
      .to raise_error(Saboteur::ConfigError, /symlink/)
  end

  it "creates private independent evidence and accepts only reviewed reasons from the proposal" do
    edit = propose
    expect(edit).not_to have_key("execution")
    expect(File.stat(@directory).mode & 0o777).to eq(0o700)
    evidence = File.join(@directory, "#{edit['token']}.json")
    expect(File.stat(evidence).mode & 0o777).to eq(0o600)
    expect(JSON.parse(File.read(evidence))["document"]["accepted"][0]["reason"]).to eq("")
    expect(store.accept(proposal: @proposal, destination: @output)).to eq(@output)
    expect(JSON.parse(File.read(@output))["accepted"][0]["reason"]).to eq("reviewed known gap")
    expect(File.exist?(evidence)).to be(false)
  end

  it "refuses overwrites, stale proposals, unknown tokens and edits to evidence even with recomputed checksums" do
    edit = propose
    expect { store.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /exists/)
    edit["document"]["metadata"]["complete"] = false
    File.write(@proposal, JSON.generate(edit))
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /evidence/)
    edit["token"] = "0" * 32
    File.write(@proposal, JSON.generate(edit))
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /evidence/)
    expect(File.exist?(@output)).to be(false)
  end

  it "requires replacement proposal and reviewer hashes to match current bytes under the lock" do
    File.write(@output, "old bytes")
    original = Digest::SHA256.file(@output).hexdigest
    propose(previous: original)
    expect do
      store.accept(proposal: @proposal, destination: @output)
    end.to raise_error(Saboteur::ConfigError, /reviewed hash/)
    expect { store.accept(proposal: @proposal, destination: @output, previous: "b" * 64) }
      .to raise_error(Saboteur::ConfigError, /reviewed hash/)
    expect(File.read(@output)).to eq("old bytes")
    File.write(@output, "concurrent update")
    expect { store.accept(proposal: @proposal, destination: @output, previous: original) }
      .to raise_error(Saboteur::ConfigError, /changed/)
    expect(File.read(@output)).to eq("concurrent update")
    File.write(@output, "old bytes")
    store.accept(proposal: @proposal, destination: @output, previous: original)
    expect(JSON.parse(File.read(@output))["format"]).to eq(1)
  end

  it "refuses blank reasons and changed input verification without touching the old file" do
    store.propose(document: document, proposal: @proposal, destination: @output)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /reason/)
    File.delete(@proposal)
    propose
    stale = described_class.new(directory: @directory, protected_paths: [], verify: ->(_) { false })
    expect { stale.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /inputs/)
    expect(File.exist?(@output)).to be(false)
  end

  it "refuses different destinations and initial destination races" do
    propose
    expect { store.accept(proposal: @proposal, destination: File.join(@root, "other.json")) }
      .to raise_error(Saboteur::ConfigError, /destination/)
    File.write(@output, "other process")
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /exists/)
    expect(File.read(@output)).to eq("other process")
  end

  it "refuses source, symlink and hardlink aliases for every written artifact" do
    protected_file = File.join(@root, "source.rb")
    File.write(protected_file, "source")
    guarded = described_class.new(directory: @directory, protected_paths: [protected_file], verify: ->(_) { true })
    expect { guarded.propose(document: document, proposal: protected_file, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /input/)
    File.link(protected_file, @output)
    expect { guarded.propose(document: document, proposal: @proposal, destination: @output, previous: "x") }
      .to raise_error(Saboteur::ConfigError, /input/)
    File.delete(@output)
    File.symlink(protected_file, @output)
    expect { guarded.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /symlink/)
    expect(File.read(protected_file)).to eq("source")
  end
  it "rejects incomplete evidence and changed inputs before publishing any proposal" do
    bad = Marshal.load(Marshal.dump(document))
    bad["metadata"]["complete"] = false
    expect { store.propose(document: bad, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /incomplete/)
    stale = described_class.new(directory: @directory, protected_paths: [], verify: ->(_) { false })
    expect { stale.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /inputs/)
    expect(File.exist?(@proposal)).to be(false)
    expect(File.exist?(@directory)).to be(false)
  end

  it "enforces path independence, missing protected markers and private evidence directories" do
    guarded = described_class.new(directory: @directory, protected_paths: [@output], verify: ->(_) { true })
    expect { guarded.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /input/)
    expect { store.propose(document: document, proposal: @output, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /alias/)
    FileUtils.mkdir_p(@directory)
    File.chmod(0o755, @directory)
    expect { propose }.to raise_error(Saboteur::ConfigError, /private/)
    expect(File.exist?(@proposal)).to be(false)
  end

  it "rejects malformed and oversized records and tokens before reads outside the evidence directory" do
    propose
    ["../outside", "", 1, "a" * 31].each do |token|
      edit = JSON.parse(File.read(@proposal))
      edit["token"] = token
      File.write(@proposal, JSON.generate(edit))
      expect { store.accept(proposal: @proposal, destination: @output) }
        .to raise_error(Saboteur::ConfigError, /token/)
    end
    [[], {}, { "extra" => true }].each do |edit|
      File.write(@proposal, JSON.generate(edit))
      expect { store.accept(proposal: @proposal, destination: @output) }
        .to raise_error(Saboteur::ConfigError, /fields/)
    end
    File.write(@proposal, "{")
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /JSON/)
    stub_const("Saboteur::Baseline::Acceptance::MAX_BYTES", 20)
    File.write(@proposal, "x" * 21)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /large/)
  end

  it "preserves old bytes and evidence on interrupted atomic publication" do
    File.write(@output, "old bytes")
    original = Digest::SHA256.file(@output).hexdigest
    edit = propose(previous: original)
    evidence = File.join(@directory, "#{edit['token']}.json")
    allow(File).to receive(:rename).and_raise(Errno::EIO)
    expect { store.accept(proposal: @proposal, destination: @output, previous: original) }
      .to raise_error(Saboteur::ConfigError, /evidence/)
    expect(File.read(@output)).to eq("old bytes")
    expect(File.exist?(evidence)).to be(true)
    expect(Dir.glob(File.join(@root, ".baseline-*"))).to be_empty
  end

  it "never follows proposal, local evidence or lock symlinks" do
    edit = propose
    evidence = File.join(@directory, "#{edit['token']}.json")
    File.symlink(@proposal, "#{@output}.lock")
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /symlink/)
    File.unlink("#{@output}.lock")
    File.unlink(evidence)
    File.symlink(@proposal, evidence)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /symlink/)
  end

  it "fails if either initial or replacement baseline state was wrong when proposed" do
    expect { store.propose(document: document, proposal: @proposal, destination: @output, previous: "a" * 64) }
      .to raise_error(Saboteur::ConfigError, /changed/)
    File.write(@output, "old")
    expect { store.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /exists/)
    expect { store.propose(document: document, proposal: @proposal, destination: @output, previous: "a" * 64) }
      .to raise_error(Saboteur::ConfigError, /changed/)
    expect(File.read(@output)).to eq("old")
  end
  it "returns the proposal token and accepts unchanged in-bound evidence at the exact size bound" do
    created = store.propose(document: document, proposal: @proposal, destination: @output)
    expect(created).to eq(JSON.parse(File.read(@proposal)))
    edited = created
    edited["document"]["accepted"][0]["reason"] = "x"
    File.write(@proposal, JSON.generate(edited))
    bound = [File.size(@proposal), File.size(File.join(@directory, "#{created['token']}.json"))].max
    stub_const("Saboteur::Baseline::Acceptance::MAX_BYTES", bound)
    expect { store.accept(proposal: @proposal, destination: @output) }.not_to raise_error
  end

  it "does not mistake unrelated files or nonexistent protected markers for hardlink aliases" do
    other = File.join(@root, "other.rb")
    File.write(other, "other")
    guarded = described_class.new(directory: @directory, protected_paths: [other, "#{other}.missing"],
                                  verify: ->(_) { true })
    File.write(@output, "old bytes")
    expect do
      guarded.propose(document: document, proposal: @proposal, destination: @output,
                      previous: Digest::SHA256.file(@output).hexdigest)
    end.not_to raise_error
  end

  it "blocks post-proposal metadata and candidate edits without relying on a proposal checksum" do
    edited = propose
    edited["document"]["metadata"]["config"]["seed"] = 2
    File.write(@proposal, JSON.generate(edited))
    expect do
      store.accept(proposal: @proposal, destination: @output)
    end.to raise_error(Saboteur::ConfigError, /evidence changed/)
    expect(File.exist?(@output)).to be(false)
    edited["document"]["metadata"]["config"]["seed"] = 1
    edited["document"]["candidates"][0]["status"] = "killed"
    File.write(@proposal, JSON.generate(edited))
    expect do
      store.accept(proposal: @proposal, destination: @output)
    end.to raise_error(Saboteur::ConfigError, /evidence changed/)
  end

  it "writes durable private temporary bytes and locks before rechecking the destination" do
    File.write(@output, "old bytes")
    original = Digest::SHA256.file(@output).hexdigest
    propose(previous: original)
    allow(File).to receive(:open).and_call_original
    expect(File).to receive(:open).with("#{@output}.lock", File::RDWR | File::CREAT | File::NOFOLLOW,
                                        0o600).and_call_original
    expect_any_instance_of(File).to receive(:flock).with(File::LOCK_EX).and_call_original
    expect_any_instance_of(File).to receive(:chmod).with(0o600).and_call_original
    expect_any_instance_of(File).to receive(:flush).and_call_original
    expect_any_instance_of(File).to receive(:fsync).and_call_original
    store.accept(proposal: @proposal, destination: @output, previous: original)
    expect(File.stat(@output).mode & 0o777).to eq(0o600)
  end

  it "rechecks aliases under lock and before exclusive evidence creation" do
    edit = propose
    protected_file = File.join(@root, "source.rb")
    File.write(protected_file, "source")
    guarded = described_class.new(directory: @directory, protected_paths: [protected_file], verify: ->(_) { true })
    allow_any_instance_of(File).to receive(:flock) do
      File.link(protected_file, @output)
      0
    end
    expect { guarded.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /input/)
    expect(File.read(protected_file)).to eq("source")
    expect(File.exist?(File.join(@directory, "#{edit['token']}.json"))).to be(true)
  end

  it "initial publication uses an exclusive link after fsync rather than exposing partial bytes" do
    propose
    expect(File).to receive(:link).and_call_original
    expect(File).not_to receive(:rename)
    store.accept(proposal: @proposal, destination: @output)
    expect(File.stat(@output).mode & 0o777).to eq(0o600)
    expect(JSON.parse(File.read(@output))["accepted"].first["reason"]).to eq("reviewed known gap")
  end
  it "rejects proposal destination collisions with canonical paths before reading records" do
    propose
    File.write(@output, File.read(@proposal))
    expect { store.accept(proposal: @output, destination: @output) }.to raise_error(Saboteur::ConfigError, /alias/)
  end

  it "writes, flushes and fsyncs independent evidence before proposal publication" do
    allow(File).to receive(:open).and_call_original
    token = "a" * 32
    allow(SecureRandom).to receive(:hex).with(16).and_return(token)
    path = File.join(@directory, "#{token}.json")
    expect(File).to receive(:open).with(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
                                  .and_call_original
    calls = []
    allow_any_instance_of(File).to receive(:flush).and_wrap_original do |method, *args|
      calls << :flush
      method.call(*args)
    end
    allow_any_instance_of(File).to receive(:fsync).and_wrap_original do |method, *args|
      calls << :fsync
      method.call(*args)
    end
    created = store.propose(document: document, proposal: @proposal, destination: @output)
    expect(JSON.parse(File.read(path))).to eq(created)
    expect(calls).to eq(%i[flush fsync flush fsync])
  end

  it "rechecks a new symlink at the actual exclusive write boundary" do
    allow(SecureRandom).to receive(:hex).with(16) do
      File.symlink(@output, @proposal)
      "a" * 32
    end
    expect { store.propose(document: document, proposal: @proposal, destination: @output) }
      .to raise_error(Saboteur::ConfigError, /symlink/)
    expect(File.exist?(@output)).to be(false)
  end
  it "rejects every nonprivate evidence permission bit" do
    FileUtils.mkdir_p(@directory)
    [0o701, 0o702, 0o704, 0o710, 0o720, 0o740].each do |mode|
      File.chmod(mode, @directory)
      expect { store.propose(document: document, proposal: @proposal, destination: @output) }
        .to raise_error(Saboteur::ConfigError, /private/)
    end
  end

  it "checks input verification both before and after acquiring the destination lock" do
    propose
    count = 0
    verifier = lambda do |_|
      count += 1
      count == 1
    end
    guarded = described_class.new(directory: @directory, protected_paths: [], verify: verifier)
    expect { guarded.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /inputs/)
    expect(count).to eq(2)
    expect(File.exist?(@output)).to be(false)
    count = 0
    expect(guarded).to receive(:verify_inputs).ordered.and_call_original
    expect(guarded).to receive(:publish).ordered.and_call_original
    expect(guarded).to receive(:verify_inputs).ordered.and_call_original
    expect { guarded.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /inputs/)
  end
  it "allows only one competing initial accept and preserves a complete winning document" do
    propose
    pipes = 2.times.map do
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        begin
          store.accept(proposal: @proposal, destination: @output)
          writer.write("accepted")
        rescue Saboteur::ConfigError
          writer.write("refused")
        ensure
          writer.close
        end
        exit! 0
      end
      writer.close
      [pid, reader]
    end
    outcomes = pipes.map do |pid, reader|
      body = reader.read
      reader.close
      Process.wait(pid)
      body
    end
    expect(outcomes.sort).to eq(%w[accepted refused])
    expect(JSON.parse(File.read(@output))["accepted"].first["reason"]).to eq("reviewed known gap")
  end

  it "leaves an initial winner unchanged when a noncooperating writer wins at the atomic link" do
    propose
    allow(File).to receive(:link).and_wrap_original do |method, *args|
      File.write(@output, "competing writer")
      method.call(*args)
    end
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /exists/)
    expect(File.read(@output)).to eq("competing writer")
    expect(Dir.glob(File.join(@root, ".baseline-*"))).to be_empty
  end

  it "refuses public local evidence and artifact paths inside the evidence directory" do
    edit = propose
    evidence = File.join(@directory, "#{edit['token']}.json")
    File.chmod(0o644, evidence)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /private/)
    expect { store.propose(document: document, proposal: File.join(@directory, "new.json"), destination: @output) }
      .to raise_error(Saboteur::ConfigError, /alias/)
    expect { store.propose(document: document, proposal: @proposal, destination: @directory) }
      .to raise_error(Saboteur::ConfigError, /alias/)
  end
  it "requires evidence files and directories owned by the current user" do
    edited = propose
    evidence = File.join(@directory, "#{edited['token']}.json")
    real_stat = File.stat(@directory)
    wrong_directory = double(mode: real_stat.mode, uid: Process.uid + 1)
    allow(File).to receive(:stat).and_call_original
    allow(File).to receive(:stat).with(@directory).and_return(wrong_directory)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /private/)
    allow(File).to receive(:stat).with(@directory).and_return(real_stat)
    wrong_evidence = double(mode: 0o600, uid: Process.uid + 1)
    allow(File).to receive(:stat).with(evidence).and_return(wrong_evidence)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /private/)
  end

  it "does not apply evidence-only permission requirements to the editable proposal" do
    propose
    File.chmod(0o644, @proposal)
    expect { store.accept(proposal: @proposal, destination: @output) }.not_to raise_error
  end

  it "checks every private record permission bit and private directory on acceptance" do
    edited = propose
    evidence = File.join(@directory, "#{edited['token']}.json")
    [0o601, 0o602, 0o604, 0o610, 0o620, 0o640].each do |mode|
      File.chmod(mode, evidence)
      expect do
        store.accept(proposal: @proposal, destination: @output)
      end.to raise_error(Saboteur::ConfigError, /private/)
    end
    File.chmod(0o600, evidence)
    File.chmod(0o755, @directory)
    expect { store.accept(proposal: @proposal, destination: @output) }.to raise_error(Saboteur::ConfigError, /private/)
    expect(File.exist?(@output)).to be(false)
  end
end
