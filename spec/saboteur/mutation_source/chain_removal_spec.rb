# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/chain_removal"

RSpec.describe Saboteur::MutationSource::ChainRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class Report\n  def run(user)\n    #{body}\n  end\nend\n").first
  end

  def bodies(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits)[/\n    (.*)\n  end\z/m, 1] }
  end

  it "removes the middle link of a three-call chain and nothing else" do
    expect(bodies("user.name.strip")).to eq(["user.strip"])
  end

  it "removes each middle link of a longer chain on its own" do
    expect(bodies("user.name.strip.upcase.to_sym")).to match_array(%w[user.strip.upcase.to_sym user.name.upcase.to_sym
                                                                      user.name.strip.to_sym])
  end

  it "has no mutant for a single call or a call on a bare name" do
    expect(bodies("user.name")).to be_empty
    expect(bodies("name.strip")).to be_empty
  end

  it "removes a link with arguments and a block whole" do
    expect(bodies("user.items.select { |i| i.ok? }.first"))
      .to match_array(["user.items.first", "user.select { |i| i.ok? }.first"])
    expect(bodies("user.items.take(2).first")).to match_array(["user.items.first", "user.take(2).first"])
  end

  it "keeps safe navigation" do
    expect(bodies("user&.name&.strip")).to eq(["user&.strip"])
  end

  it "handles leading-dot chains across lines" do
    expect(bodies("user\n      .name\n      .strip")).to eq(["user\n      .strip"])
  end

  it "skips operators, index calls, attribute writes and identity calls" do
    expect(bodies("user.a + user.b")).to be_empty
    expect(bodies("user.list[0].name")).to be_empty
    expect(bodies("user.name = 1")).to be_empty
    expect(bodies("user.name.freeze.strip")).to eq(["user.freeze.strip"])
  end

  it "leaves attribute writes and operator-assigns alone" do
    expect(bodies("user.profile.name = 1")).to be_empty
    expect(bodies("user.profile.count += 1")).to be_empty
    expect(bodies("user.profile.name ||= 1")).to be_empty
    expect(bodies("user.profile.name = user.account.id")).to eq(["user.profile.name = user.id"])
  end

  it "skips a call written with .() because it has no method name to remove" do
    expect(bodies("user.items.(1).first")).to eq(["user.(1).first"])
  end

  it "does not look inside nested definitions" do
    expect(bodies("def helper(x)\n      x.a.b\n    end")).to be_empty
  end

  it "skips statements the arid patterns exclude" do
    expect(bodies("Rails.logger.info.debug(user)")).to be_empty
  end

  it "reports the operator and source as chain_removal and is not coarse" do
    mutation = source.mutations_for(subject_for("user.name.strip")).first
    expect([mutation.operator, mutation.source, mutation.coarse]).to eq(["chain_removal", "chain_removal", false])
  end

  it "changes behaviour a test can observe" do
    subject = subject_for("user.name.strip")
    mutation = source.mutations_for(subject).first
    user = Struct.new(:name).new("  ann ")
    original = Class.new { class_eval(subject.source) }.new.run(user)
    expect(original).to eq("ann")
    expect { Class.new { class_eval(subject.apply(mutation.edits)) }.new.run(user) }.to raise_error(NoMethodError)
  end
end
