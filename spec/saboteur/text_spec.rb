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

    it "escapes control characters so an injected newline cannot start a command line (#834)" do
      expect(described_class.display_safe("ok\n::error::boom")).to eq("ok\\x0a::error::boom")
      expect(described_class.display_safe("a\t b\x7f")).to eq("a\\x09 b\\x7f")
    end
  end
end
