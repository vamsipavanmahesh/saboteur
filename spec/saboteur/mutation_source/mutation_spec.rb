# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::Mutation do
  it "hashes bytes, not encodings: a UTF-8 replacement over a binary source with high bytes digests fine" do
    source = +"# caf\xC3\xA9\n".dup.force_encoding(Encoding::BINARY)
    source << "def total(a, b) = a + b\n"
    edit = Saboteur::MutationSource::Edit.new(file: "m.rb", start_byte: source.bytesize - 2,
                                              end_byte: source.bytesize - 1, replacement: "max")
    mutation = described_class.new(subject_id: "M#total", operator: "method_swap", edits: [edit])

    expect { mutation.digest(subject_start: 8, original_source: source) }.not_to raise_error
    # The same bytes with UTF-8 encoding must give the same id.
    utf8_source = source.dup.force_encoding(Encoding::UTF_8)
    utf8_edit = Saboteur::MutationSource::Edit.new(file: "m.rb", start_byte: edit.start_byte,
                                                   end_byte: edit.end_byte, replacement: "max")
    utf8_mutation = described_class.new(subject_id: "M#total", operator: "method_swap", edits: [utf8_edit])
    expect(mutation.digest(subject_start: 8, original_source: source))
      .to eq(utf8_mutation.digest(subject_start: 8, original_source: utf8_source))
  end
end
