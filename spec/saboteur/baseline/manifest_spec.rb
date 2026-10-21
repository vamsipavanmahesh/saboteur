# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/manifest"
require "saboteur/baseline/identity"

RSpec.describe Saboteur::Baseline::Manifest do
  let(:identity) do
    Saboteur::Baseline::Identity.new(subject: person_subject, mutation: comparison_mutation,
                                     root: File.dirname(person_subject.file))
  end
  let(:candidate) { identity.entry.merge("status" => "survived", "kill_cause" => nil) }
  let(:metadata) do
    { "generator" => { "version" => Saboteur::VERSION, "sources" => ["builtin"] },
      "runtime" => { "engine" => "ruby", "version" => "3.4.3", "platform" => "linux" },
      "config" => { "subjects" => [], "seed" => 1 }, "scope" => { "include" => ["lib/**/*.rb"] },
      "snapshot" => { "digest" => "a" * 64 }, "subjects" => [["person.rb", "Person#adult?"]],
      "complete" => true, "issues" => [] }
  end
  let(:acceptance) do
    { "id" => identity.id, "context" => identity.context, "reason" => "equivalent under integer ages" }
  end
  let(:document) do
    { "format" => 1, "identity_version" => 1, "metadata" => metadata,
      "candidates" => [candidate], "accepted" => [acceptance] }
  end

  it "validates complete evidence and retains canonical full identities and reasons" do
    value = described_class.new(document)
    expect(value.to_h).to eq(document)
    expect(value.candidates).to eq(identity.id => candidate)
    expect(value.accepted).to eq(identity.id => acceptance)
    expect(value.compatibility).to eq(metadata.slice("generator", "runtime", "config", "scope"))
    expect(value.to_h).to be_frozen
  end

  def refuse(changed, message)
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, message)
  end

  it "rejects unknown formats, wrong types, unknown fields and missing metadata" do
    refuse(document.merge("format" => 2), /format/)
    refuse(document.merge("identity_version" => 2), /identity/)
    refuse(document.except("identity_version"), /manifest fields/)
    refuse(document.merge("extra" => true), /fields/)
    refuse(document.merge("candidates" => nil), /candidates/)
    refuse(document.merge("metadata" => metadata.except("config")), /metadata/)
    refuse(document.merge("metadata" => metadata.merge("complete" => false)), /incomplete/)
    refuse(document.merge("metadata" => metadata.merge("issues" => ["input_changed"])), /incomplete/)
    refuse(document.merge("metadata" => metadata.merge("subjects" => [])), /subject/)
  end

  it "rejects corrupt hashes, tuples, contexts, statuses and duplicate identities" do
    refuse(document.merge("candidates" => []), /empty/)
    refuse(document.merge("candidates" => [candidate, candidate]), /duplicate/)
    %w[skipped error resource_limit unknown].each do |status|
      refuse(document.merge("candidates" => [candidate.merge("status" => status)]), /status/)
    end
    refuse(document.merge("candidates" => [candidate.merge("id" => "0" * 64)]), /identity/)
    refuse(document.merge("candidates" => [candidate.merge("context" => "x")]), /context/)
    bad = candidate["identity"].dup
    bad[1] = "../person.rb"
    refuse(document.merge("candidates" => [candidate.merge("identity" => bad)]), /path/)
    bad[1] = "person.rb"
    bad[-1] = [[0, 1, "ff", "zz"]]
    refuse(document.merge("candidates" => [candidate.merge("identity" => bad)]), /edit/)
  end

  it "rejects incomplete acceptance, stale contexts, killed acceptance and blank reasons" do
    refuse(document.merge("accepted" => []), /acceptance/)
    refuse(document.merge("accepted" => [acceptance, acceptance]), /duplicate/)
    refuse(document.merge("accepted" => [acceptance.merge("id" => "b" * 64)]), /acceptance/)
    refuse(document.merge("accepted" => [acceptance.merge("context" => "c" * 64)]), /context/)
    ["", " \n", nil, 3].each do |reason|
      refuse(document.merge("accepted" => [acceptance.merge("reason" => reason)]), /reason/)
    end
    refuse(document.merge("candidates" => [candidate.merge("status" => "killed")]), /acceptance/)
    expect(described_class.new(document.merge("candidates" => [candidate.merge("status" => "timeout")],
                                              "accepted" => [])).accepted).to be_empty
  end

  it "does not equate code snapshots or subject inventories with comparison compatibility" do
    one = described_class.new(document)
    newer = document.merge("metadata" => metadata.merge("snapshot" => { "digest" => "b" * 64 }))
    expect(described_class.new(newer).compatibility).to eq(one.compatibility)
    changed = document.merge("metadata" => metadata.merge("config" => { "subjects" => ["Person"], "seed" => 1 }))
    expect(described_class.new(changed).compatibility).not_to eq(one.compatibility)
  end

  it "rejects ambiguous subjects and mutable nested evidence" do
    refuse(document.merge("metadata" => metadata.merge("subjects" => metadata["subjects"] * 2)), /duplicate/)
    value = described_class.new(document)
    document["candidates"][0]["context"] = "edited"
    expect(value.to_h["candidates"][0]["identity"][1]).to eq("person.rb")
    expect { value.to_h["metadata"]["config"]["seed"] = 2 }.to raise_error(FrozenError)
  end
  def with_tuple(tuple)
    entry = candidate.merge("identity" => tuple, "id" => Digest::SHA256.hexdigest(JSON.generate(tuple)))
    document.merge("candidates" => [entry], "accepted" => [acceptance.merge("id" => entry["id"])])
  end

  it "checks every metadata and subject field, not just completion" do
    %w[generator runtime config scope snapshot].each do |key|
      [nil, [], {}].each { |value| refuse(document.merge("metadata" => metadata.merge(key => value)), /metadata/) }
    end
    [nil, {}, [nil], [["person.rb"]], [["person.rb", ""]], [["/a.rb", "A#m"]]].each do |subjects|
      refuse(document.merge("metadata" => metadata.merge("subjects" => subjects)), /subject|path/)
    end
    refuse(document.merge("metadata" => metadata.merge("subjects" => [["other.rb", "Other#m"]])), /subject/)
  end

  it "checks tuple types, version, text and coarse flag even with recomputed hashes" do
    [nil, {}, [], [1], [2, *candidate["identity"][1..]]].each do |tuple|
      refuse(with_tuple(tuple), /identity/)
    end
    [2, 3, 4].each do |position|
      [nil, 1, "", " ", "a\0b"].each do |bad|
        tuple = Marshal.load(Marshal.dump(candidate["identity"]))
        tuple[position] = bad
        refuse(with_tuple(tuple), /identity/)
      end
    end
    [nil, 0, "false"].each do |bad|
      tuple = Marshal.load(Marshal.dump(candidate["identity"]))
      tuple[5] = bad
      refuse(with_tuple(tuple), /coarse/)
    end
  end

  it "validates paths without accepting dot, parent, absolute or empty components" do
    ["", "a\0b", ".", "..", "../a.rb", "a/./b", "a//b", "a/", "a\\b", "/a"].each do |bad|
      tuple = Marshal.load(Marshal.dump(candidate["identity"]))
      tuple[1] = bad
      refuse(with_tuple(tuple), /path/)
    end
  end

  it "checks edit shape, exact byte lengths, boundaries and order" do
    bad_edits = [nil, {}, [], [nil], [[0, 1]], [[-1, 1, "", ""]], [[0, -1, "", ""]],
                 [[0, "1", "", ""]], [["0", 1, "", ""]], [[0, 1, "", ""]],
                 [[0, 0, nil, ""]], [[0, 0, "", 1]], [[0, 0, "a", ""]],
                 [[0, 2, "aabb", ""], [1, 2, "aa", ""]],
                 [[0, 1, "aa", ""], [1, 3, "bbbb", ""], [2, 3, "bb", ""]]]
    bad_edits.each do |edits|
      tuple = Marshal.load(Marshal.dump(candidate["identity"]))
      tuple[6] = edits
      refuse(with_tuple(tuple), /edit/)
    end
    tuple = Marshal.load(Marshal.dump(candidate["identity"]))
    tuple[6] = [[0, 0, "", ""], [0, 1, "aa", "ff"], [1, 1, "", ""]]
    expect(described_class.new(with_tuple(tuple)).candidates.values.first["identity"].last).to eq(tuple[6])
  end

  it "validates causes, acceptance field shape and SHA-256 context length" do
    valid = candidate.merge("status" => "killed", "kill_cause" => "assertion")
    expect(described_class.new(document.merge("candidates" => [valid], "accepted" => [])).candidates.values)
      .to eq([valid])
    ["", 0, "x\0y"].each do |cause|
      refuse(document.merge("candidates" => [candidate.merge("kill_cause" => cause)]), /cause/)
    end
    [nil, {}, "x"].each { |bad| refuse(document.merge("accepted" => bad), /accepted/) }
    refuse(document.merge("accepted" => [acceptance.merge("extra" => 1)]), /fields/)
    [nil, 64, "g" * 64, "a" * 63, "a" * 65].each do |bad|
      refuse(document.merge("candidates" => [candidate.merge("context" => bad)]), /context/)
    end
  end
  it "freezes every nested key, array and string, not only the outer hash" do
    value = described_class.new(document)
    expect(value.candidates).to be_frozen
    expect(value.accepted).to be_frozen
    expect(value.to_h["candidates"]).to be_frozen
    expect(value.to_h["candidates"][0]["id"]).to be_frozen
    expect(value.to_h["candidates"][0]["identity"]).to be_frozen
    expect(value.to_h["candidates"][0]["identity"].last.first).to be_frozen
    expect(value.to_h.keys.first).to be_frozen
  end

  it "rejects malformed metadata and arrays at their own boundary" do
    refuse(document.merge("metadata" => nil), /metadata fields/)
    refuse(document.merge("metadata" => metadata.merge("subjects" => [])), /subject inventory/)
    [["person.rb", "Person#adult?", "extra"], ["../a", "Person#adult?"], ["person.rb", ""]].each do |entry|
      expected = if entry.size == 3
                   /subject entry/
                 else
                   (entry.first == "person.rb" ? /invalid subject$/ : /invalid path$/)
                 end
      refuse(document.merge("metadata" => metadata.merge("subjects" => [entry])), expected)
    end
    [1, { "path" => "person.rb" }].each do |entry|
      refuse(document.merge("metadata" => metadata.merge("subjects" => [entry])), /subject entry/)
    end
    [1, {}, nil].each { |entry| refuse(document.merge("candidates" => [entry]), /candidate fields/) }
    tuple = Marshal.load(Marshal.dump(candidate["identity"]))
    tuple[3] = ""
    refuse(with_tuple(tuple), /identity text/)
    tuple = Marshal.load(Marshal.dump(candidate["identity"]))
    tuple[6] = [[0, 1, "aa", "", 0]]
    refuse(with_tuple(tuple), /identity edit$/)
    tuple[6] = [[-1, 0, "aa", ""]]
    refuse(with_tuple(tuple), /identity edit range/)
    tuple[6] = [[0, -1, "", ""]]
    refuse(with_tuple(tuple), /identity edit range/)
    tuple[6] = [[0, 1, "aa", ""], [3, 4, "aa", ""]]
    expect(described_class.new(with_tuple(tuple)).candidates.size).to eq(1)
    refuse(document.merge("candidates" => [candidate.merge("status" => "killed")]), /acceptance candidate/)
    refuse(document.merge("accepted" => [nil]), /acceptance fields/)
    bad_tuple = Marshal.load(Marshal.dump(candidate["identity"]))
    bad_tuple[1] = "a/../b"
    refuse(with_tuple(bad_tuple), /invalid path$/)
  end
  it "checks contexts even on nonaccepted detected candidates and rejects trailing parents" do
    valid = candidate.merge("status" => "killed")
    refuse(document.merge("candidates" => [valid.merge("context" => "x")], "accepted" => []), /context/)
    tuple = Marshal.load(Marshal.dump(candidate["identity"]))
    tuple[1] = "a/b/.."
    refuse(with_tuple(tuple), /path/)
  end

  it "accepts proposable metadata with only soft gaps, plus legacy metadata without the key" do
    gapped = document.merge("metadata" => metadata.merge("complete" => false, "proposable" => true,
                                                         "issues" => ["subject_skipped:person.rb:Person#other"]))
    expect(described_class.new(gapped).to_h.fetch("metadata").fetch("proposable")).to be(true)
    legacy = document.merge("metadata" => metadata.slice(*Saboteur::Baseline::Manifest::LEGACY_METADATA))
    expect { described_class.new(legacy) }.not_to raise_error
    refuse(document.merge("metadata" => metadata.merge("proposable" => true,
                                                       "issues" => ["missing_result:x"])), /incomplete evidence/)
    refuse(document.merge("metadata" => metadata.merge("proposable" => false)), /incomplete evidence/)
  end
end
