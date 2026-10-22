# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Text do
  it "rejects invalid UTF-8 with a parse error naming the problem" do
    expect { described_class.utf8_strict("\xFF".b) }.to raise_error(JSON::ParserError, "invalid UTF-8")
  end

  it "returns valid input retagged as UTF-8" do
    expect(described_class.utf8_strict("ok".b)).to eq("ok")
  end

  describe ".name_list" do
    it "names every item up to the limit, with no tail" do
      expect(described_class.name_list(%w[a b c])).to eq("a, b, c")
      expect(described_class.name_list(%w[a b c d e])).to eq("a, b, c, d, e")
    end

    it "names the first five and counts the rest" do
      expect(described_class.name_list(%w[a b c d e f])).to eq("a, b, c, d, e and 1 more")
      expect(described_class.name_list((1..9).map(&:to_s))).to eq("1, 2, 3, 4, 5 and 4 more")
    end

    it "takes another limit" do
      expect(described_class.name_list(%w[a b c], limit: 2)).to eq("a, b and 1 more")
    end

    it "returns an empty string for no items" do
      expect(described_class.name_list([])).to eq("")
    end

    it "escapes items that read as CI workflow commands (#834)" do
      expect(described_class.name_list(["ok\n::error::x.rb", "b##[warning]c.rb"]))
        .to eq("ok\\x0a::error::x.rb, b##\\x5bwarning]c.rb")
    end
  end

  describe ".display_safe_lines" do
    it "keeps the message's own line breaks and breaks a command on any line" do
      expect(described_class.display_safe_lines("fix it\n  detail\n::error::injected"))
        .to eq("fix it\n  detail\n\\x3a:error::injected")
    end

    it "escapes other control characters and an Azure command on any line" do
      expect(described_class.display_safe_lines("a\r\e[2Jb\nsee ##[error]x"))
        .to eq("a\\x0d\\x1b[2Jb\nsee ##\\x5berror]x")
    end

    it "keeps a trailing newline and is unchanged by a second pass" do
      once = described_class.display_safe_lines("x\n::error::y\n")
      expect(once).to end_with("\n")
      expect(described_class.display_safe_lines(once)).to eq(once)
    end

    it "keeps blank lines and leading newlines" do
      expect(described_class.display_safe_lines("\n\na\n\n::error::b\n\n"))
        .to eq("\n\na\n\n\\x3a:error::b\n\n")
    end

    it "escapes a carriage return before a line break" do
      expect(described_class.display_safe_lines("a\r\n::error::b")).to eq("a\\x0d\n\\x3a:error::b")
    end

    it "leaves a clean multi-line message alone" do
      message = "run it\n  Saboteur::Error: cause [1]"
      expect(described_class.display_safe_lines(message)).to eq(message)
    end
  end

  describe ".display_safe" do
    it "breaks a GitHub workflow command at the start of the text (#834)" do
      expect(described_class.display_safe("::error::boom=1")).to eq("\\x3a:error::boom=1")
      expect(described_class.display_safe("  ::warning::hey")).to eq("  \\x3a:warning::hey")
    end

    it "breaks an Azure DevOps command anywhere in the text (#834)" do
      expect(described_class.display_safe("see ##[warning]here")).to eq("see ##\\x5bwarning]here")
    end

    it "leaves ordinary colons and brackets alone" do
      expect(described_class.display_safe("Saboteur::Error [1]")).to eq("Saboteur::Error [1]")
      expect(described_class.display_safe("a: b")).to eq("a: b")
    end

    it "scrubs invalid UTF-8 instead of raising (#834)" do
      expect(described_class.display_safe("a\xffb".dup.force_encoding(Encoding::UTF_8))).to eq("a�b")
      injected = "\xff\n::error::x".dup.force_encoding(Encoding::UTF_8)
      expect(described_class.display_safe(injected)).to eq("�\\x0a::error::x")
    end

    it "counts nouns in the singular and plural (C9)" do
      expect(described_class.counted(1, "subject")).to eq("1 subject")
      expect(described_class.counted(0, "subject")).to eq("0 subjects")
      expect(described_class.counted(2, "mutant")).to eq("2 mutants")
    end

    it "escapes control characters so an injected newline cannot start a command line (#834)" do
      expect(described_class.display_safe("ok\n::error::boom")).to eq("ok\\x0a::error::boom")
      expect(described_class.display_safe("a\t b\x7f")).to eq("a\\x09 b\\x7f")
    end
  end
end
