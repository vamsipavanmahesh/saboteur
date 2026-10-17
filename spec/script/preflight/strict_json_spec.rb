# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"
require "tmpdir"

RSpec.describe Preflight::StrictJson do
  let(:directory) { Dir.mktmpdir("strict-json") }

  after { FileUtils.remove_entry(directory) }

  it "reads a regular JSON file (valid control)" do
    path = File.join(directory, "ok.json")
    File.write(path, '{"a": 1}')
    expect(described_class.read(path)).to eq("a" => 1)
  end

  it "rejects a FIFO without hanging" do
    path = File.join(directory, "fifo.json")
    File.mkfifo(path)
    expect { described_class.read(path) }.to raise_error(Preflight::MalformedDocument, /not a regular file/)
  end

  it "rejects a missing file and a directory as malformed documents, not as raw errors" do
    expect { described_class.read(File.join(directory, "none.json")) }.to raise_error(Preflight::MalformedDocument)
    expect { described_class.read(directory) }.to raise_error(Preflight::MalformedDocument)
  end

  it "rejects duplicate keys, invalid UTF-8 and oversized input" do
    expect { described_class.parse('{"a":1,"a":2}') }.to raise_error(Preflight::MalformedDocument, /duplicate/)
    expect { described_class.parse("{\"a\":\"\xff\"}".b) }.to raise_error(Preflight::MalformedDocument, /UTF-8/)
    stub_const("Preflight::StrictJson::MAX_BYTES", 4)
    expect { described_class.parse("[1,2,3]") }.to raise_error(Preflight::MalformedDocument, /over/)
  end

  it "digests a regular file and refuses a FIFO without hanging" do
    path = File.join(directory, "d")
    File.write(path, "abc")
    expect(described_class.digest(path)).to eq(Digest::SHA256.hexdigest("abc"))
    fifo = File.join(directory, "f")
    File.mkfifo(fifo)
    expect { Timeout.timeout(5) { described_class.digest(fifo) } }.to raise_error(Preflight::MalformedDocument)
  end

  it "bounds a digest at the byte cap it is given (#364)" do
    path = File.join(directory, "d")
    File.write(path, "abc")
    expect(described_class.digest(path, max_bytes: 3)).to eq(Digest::SHA256.hexdigest("abc"))
    expect { described_class.digest(path, max_bytes: 2) }.to raise_error(Preflight::MalformedDocument, /over 2 bytes/)
  end
end
