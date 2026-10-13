# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The lib files are written by the e2e spec, byte for byte: a CRLF file and
# a BOM file kept in git would be rewritten by autocrlf or an editor.
require_relative "../lib/crlf"
require_relative "../lib/bom"
require_relative "../lib/multibyte"

RSpec.describe "encodings" do
  it("adds in a CRLF file") { expect(Crlf.new.total(1, 2)).to eq(3) }
  it("adds zero in a CRLF file") { expect(Crlf.new.total(5, 0)).to eq(5) }
  it("adds in a BOM file") { expect(Bom.new.total(1, 2)).to eq(3) }
  it("adds zero in a BOM file") { expect(Bom.new.total(5, 0)).to eq(5) }
  it("adds after multibyte text") { expect(Multibyte.new.total(1, 2)).to eq("\u00e9\u00e93") }
  it("adds zero after multibyte text") { expect(Multibyte.new.total(0, 0)).to eq("\u00e9\u00e90") }
end
