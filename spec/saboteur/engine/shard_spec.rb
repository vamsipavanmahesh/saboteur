# SPDX-License-Identifier: MIT
# frozen_string_literal: true

ShardSubjectStub = Struct.new(:id, :start_byte, :file_source)

class ShardMutationStub
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def digest(**)
    value
  end
end

RSpec.describe Saboteur::Engine::Shard do
  def subject(id)
    ShardSubjectStub.new(id, 0, "def #{id}; end\n")
  end

  def candidates(*digests)
    digests.map { |digest| [ShardMutationStub.new(digest), "mutated #{digest}"] }
  end

  it "requires a positive k/n pair inside the range" do
    expect(described_class.parse("1/2")).to have_attributes(index: 1, total: 2)
    expect { described_class.parse("0/2") }.to raise_error(Saboteur::ConfigError, /shard/)
    expect { described_class.parse("1/1") }.to raise_error(Saboteur::ConfigError, /shard/)
    expect { described_class.parse("3/2") }.to raise_error(Saboteur::ConfigError, /shard/)
    expect { described_class.parse("one/two") }.to raise_error(Saboteur::ConfigError, /shard/)
  end

  it "partitions the same planned inventory without overlap" do
    subjects = [subject("A#one"), subject("B#two")]
    lists = [candidates("a1", "a2", "a3"), candidates("b1", "b2")]
    shards = (1..4).map do |index|
      shard = described_class.parse("#{index}/4")
      shard.select(subjects, lists)
      shard
    end

    selected = shards.flat_map(&:selected_keys)
    expect(selected).to match_array(shards.first.all_keys)
    expect(selected.uniq).to eq(selected)
    expect(shards.map(&:inventory_digest).uniq.one?).to be(true)
    expect(shards.first.planned_count).to eq(5)
    expect(shards.sum(&:selected_count)).to eq(5)
    expected_keys = subjects.zip(lists).flat_map do |selected_subject, list|
      list.map { |mutation, _| "#{selected_subject.id} #{mutation.value}" }
    end
    expect(shards.first.inventory_digest)
      .to eq(Digest::SHA256.hexdigest(expected_keys.sort.join(described_class::INVENTORY_JOINER)))
  end

  it "gives the same inventory digest for any input order" do
    subjects = [subject("A#one")]
    forward = described_class.parse("1/2")
    forward.select(subjects, [candidates("a1", "a2")])
    backward = described_class.parse("1/2")
    backward.select(subjects, [candidates("a2", "a1")])
    expect(backward.inventory_digest).to eq(forward.inventory_digest)
  end

  it "keeps candidates in subject order inside the selected shard" do
    subjects = [subject("A#one")]
    lists = [candidates("a1", "a2", "a3", "a4")]
    shard = described_class.parse("1/2")
    selected = shard.select(subjects, lists)
    keys = shard.selected_keys
    expect(selected.first.map { |mutation, _| mutation.value })
      .to eq(lists.first.map { |mutation, _| mutation.value }.select do |digest|
        keys.include?("A#one #{digest}")
      end)
  end

  it "prints the selected count, planned count and inventory digest" do
    subjects = [subject("A#one")]
    lists = [candidates("a1", "a2")]
    shard = described_class.parse("1/2")
    shard.select(subjects, lists)
    expected = ["Shard 1/2: #{shard.selected_count} of 2 planned mutants; ",
                "inventory sha256:#{shard.inventory_digest}; partial run"].join
    expect(shard.line).to eq(expected)
  end
end
