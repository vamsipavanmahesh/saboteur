# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/identity"

RSpec.describe Saboteur::Baseline::Identity do
  let(:root) { File.dirname(person_subject.file) }
  let(:identity) { described_class.new(subject: person_subject, mutation: comparison_mutation, root: root) }

  it "records versioned readable file, subject and mutation identity with a full SHA-256" do
    expect(identity.tuple).to eq([1, "person.rb", "Person#adult?", "builtin", "comparison", false,
                                  [[17, 19, "3e3d", "3e"]]])
    expect(identity.id).to eq(Digest::SHA256.hexdigest(JSON.generate(identity.tuple)))
    expect(identity.context).to eq(Digest::SHA256.hexdigest(person_subject.source.b))
    expect(identity.entry).to eq("id" => identity.id, "identity" => identity.tuple, "context" => identity.context)
  end

  it "copies and deeply freezes identity values under the computed digest" do
    origin = +"external"
    operator = +"change"
    value = identified(origin: origin, operator: operator)
    origin.replace("changed")
    operator.replace("changed")
    expect(value.tuple[3..4]).to eq(%w[external change])
    expect { value.tuple.last.first << "other" }.to raise_error(FrozenError)
    expect { value.tuple.last.first.last.replace("00") }.to raise_error(FrozenError)
    expect { value.tuple[3].replace("other") }.to raise_error(FrozenError)
    expect(value.id).to eq(Digest::SHA256.hexdigest(JSON.generate(value.tuple)))
  end

  def identified(source: ReportHelpers::PERSON, file: "person.rb", operator: "comparison", origin: "builtin",
                 coarse: false)
    subject = subjects_in(source, name: file).first
    offset = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: offset, end_byte: offset + 2,
                                              replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: operator, source: origin,
                                                      coarse: coarse, edits: [edit])
    described_class.new(subject: subject, mutation: mutation, root: File.dirname(subject.file))
  end

  it "is stable across checkout roots and line shifts before a method" do
    shifted = identified(source: "# inserted\n#{ReportHelpers::PERSON}")
    expect(shifted.id).to eq(identity.id)
    expect(shifted.context).to eq(identity.context)
  end

  it "changes on file, subject, source, operator, replacement and coarse identity changes" do
    expect(identified(file: "other.rb").id).not_to eq(identity.id)
    expect(identified(source: ReportHelpers::PERSON.sub("Person", "Other")).id).not_to eq(identity.id)
    expect(identified(operator: "other").id).not_to eq(identity.id)
    expect(identified(origin: "custom").id).not_to eq(identity.id)
    expect(identified(coarse: true).id).not_to eq(identity.id)
    changed = described_class.new(subject: person_subject, mutation: comparison_mutation(replacement: "<"), root: root)
    expect(changed.id).not_to eq(identity.id)
  end

  it "keeps changed subject context separate from an unchanged local mutation" do
    changed = identified(source: ReportHelpers::PERSON.sub("18", "21"))
    expect(changed.id).to eq(identity.id)
    expect(changed.context).not_to eq(identity.context)
  end

  it "sorts edits and encodes exact bytes without delimiter or encoding collisions" do
    offset = person_subject.file_source.index("18")
    other = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: offset, end_byte: offset + 2,
                                               replacement: "\x00\xff".b)
    edits = comparison_mutation.edits + [other]
    mutation = comparison_mutation.with(edits: edits.reverse)
    ordered = described_class.new(subject: person_subject, mutation: mutation.with(edits: edits), root: root)
    reversed = described_class.new(subject: person_subject, mutation: mutation, root: root)
    expect(reversed.id).to eq(ordered.id)
    expect(ordered.tuple.last.last.last).to eq("00ff")
  end

  it "rejects subjects outside the project and edits outside or in another file" do
    expect { described_class.new(subject: person_subject, mutation: comparison_mutation, root: "/other") }
      .to raise_error(Saboteur::ConfigError, /outside/)
    edit = comparison_mutation.edits.first
    [edit.with(file: "elsewhere.rb"), edit.with(start_byte: 0), edit.with(end_byte: person_subject.end_byte + 1),
     Struct.new(:file, :start_byte, :end_byte).new(edit.file, edit.start_byte, edit.start_byte - 1)].each do |invalid|
      expect do
        described_class.new(subject: person_subject, mutation: comparison_mutation.with(edits: [invalid]), root: root)
      end
        .to raise_error(Saboteur::ConfigError, /edit/)
    end
  end

  it "accepts exact method boundaries, insertion edits and touching nonoverlapping edits" do
    first = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: person_subject.start_byte,
                                               end_byte: person_subject.start_byte, replacement: " ")
    second = first.with(end_byte: person_subject.end_byte, replacement: "def adult?; false; end")
    mutation = comparison_mutation.with(edits: [first, second])
    value = described_class.new(subject: person_subject, mutation: mutation, root: root)
    expect(value.tuple.last.first).to eq([0, 0, "", "20"])
    expect(value.tuple.last.last[0..1]).to eq([0, person_subject.source.bytesize])
    parent_path = File.join(person_subject.file, "child")
    expect { described_class.new(subject: person_subject, mutation: comparison_mutation, root: parent_path) }
      .to raise_error(Saboteur::ConfigError, /outside/)
  end

  it "refuses inconsistent subject identifiers and overlapping edits" do
    expect do
      described_class.new(subject: person_subject, mutation: comparison_mutation.with(subject_id: "Other#method"),
                          root: root)
    end.to raise_error(Saboteur::ConfigError, /subject/)
    duplicates = comparison_mutation.with(edits: comparison_mutation.edits * 2)
    expect do
      described_class.new(subject: person_subject, mutation: duplicates,
                          root: root)
    end.to raise_error(Saboteur::ConfigError, /overlap/)
  end
end
