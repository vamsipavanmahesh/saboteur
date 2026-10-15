# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::Mutation do
  # The digest hashes bytes, not encodings: a binary-read source with high
  # bytes, a UTF-8 replacement with high bytes and a non-ASCII subject id
  # (Ruby allows Unicode method names) must digest fine, and the same bytes
  # must give the same id however they are encoded. Joining any of these
  # without .b raises Encoding::CompatibilityError.
  it "digests non-ASCII originals, replacements and subject ids as bytes" do
    source = +"def total = \"caf\xC3\xA9\"\n".dup.force_encoding(Encoding::BINARY)
    edit = Saboteur::MutationSource::Edit.new(file: "m.rb", start_byte: 13, end_byte: 18,
                                              replacement: (+"th\xC3\xA9").force_encoding(Encoding::UTF_8))
    mutation = described_class.new(subject_id: (+"M#caf\xC3\xA9").force_encoding(Encoding::UTF_8),
                                   operator: "literal_string", edits: [edit])

    expect { mutation.digest(subject_start: 0, original_source: source) }.not_to raise_error

    utf8_edit = Saboteur::MutationSource::Edit.new(file: "m.rb", start_byte: 13, end_byte: 18,
                                                   replacement: edit.replacement)
    utf8_mutation = described_class.new(subject_id: mutation.subject_id, operator: "literal_string",
                                        edits: [utf8_edit])
    utf8_source = source.dup.force_encoding(Encoding::UTF_8)
    expect(mutation.digest(subject_start: 0, original_source: source))
      .to eq(utf8_mutation.digest(subject_start: 0, original_source: utf8_source))
  end
end
