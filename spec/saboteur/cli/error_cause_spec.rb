# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Saboteur::CLI::ErrorCause do
  def result(reason)
    Struct.new(:reason).new(reason)
  end

  describe ".line" do
    it "is empty when no result carries a reason" do
      expect(described_class.line([result(nil), result("")])).to eq("")
      expect(described_class.line([])).to eq("")
    end

    it "names the most common cause with its count out of all errored results" do
      errored = [
        result("worker 1 died (signal KILL), running this item"),
        result("boom"),
        result("worker 12 died (signal KILL), running this item"),
        result(nil)
      ]

      expect(described_class.line(errored)).to eq(
        "\n  most common cause (2 of 4): worker 1 died (signal KILL), running this item"
      )
    end

    it "does not group a reason with a number and the same text without one" do
      errored = [result("code 1"), result("code 2"), result("code ")]

      expect(described_class.line(errored)).to eq("\n  most common cause (2 of 3): code 1")
    end

    it "survives a reason with invalid UTF-8" do
      reason = "a\xffb\n".dup.force_encoding(Encoding::UTF_8)

      expect(described_class.line([result(reason)])).to eq("\n  most common cause (1 of 1): a\uFFFDb")
    end

    it "strips colors and escapes control characters in a reason" do
      reason = "boom \e[31m\e[K\rgone \u009b"

      expect(described_class.line([result(reason)])).to eq(
        "\n  most common cause (1 of 1): boom \\x0dgone \\x9b"
      )
    end

    it "neutralizes ANSI, NUL, workflow commands and a huge tail in one reason" do
      reason = "\e[2J\e]0;pwn\a##[error]x\r::error::forged\0#{'A' * 5000}"
      out = described_class.line([result(reason)])

      expect(out).to start_with(
        "\n  most common cause (1 of 1): \\x1b]0;pwn\\x07##\\x5berror]x\\x0d::error::forged\\x00AAA"
      )
      expect(out).to end_with("A...")
      expect(out.size).to be < 260
      expect(out).not_to match(/[\x00-\x09\x0b-\x1f\x7f]/)
    end

    it "breaks a leading :: so the line is not a workflow command" do
      expect(described_class.line([result("  ::error::x")])).to eq("\n  most common cause (1 of 1): \\x3a:error::x")
    end

    it "caps a very long reason at 200 characters with an ellipsis" do
      line = described_class.line([result("x" * 100_000), result("y" * 200)])

      expect(line).to eq("\n  most common cause (1 of 2): #{'x' * 200}...")
      expect(described_class.line([result("y" * 200)])).to end_with("y" * 200)
    end

    it "falls back to a plain dump when scrubbing raises" do
      allow(Saboteur::Text).to receive(:utf8).and_raise(EncodingError)

      expect(described_class.line([result("a\tb")])).to eq("\n  most common cause (1 of 1): \"a\\tb\"")
      expect(described_class.line([result(:boom)])).to eq("\n  most common cause (1 of 1): \"boom\"")
    end

    it "uses only the first line of a reason" do
      expect(described_class.line([result("first\nsecond")])).to eq("\n  most common cause (1 of 1): first")
    end
  end

  describe ".incomplete" do
    it "states the count and appends the cause line" do
      expect(described_class.incomplete([result("boom"), result(nil)])).to eq(
        "saboteur: 2 mutant(s) errored or hit a resource limit, so the score is incomplete" \
        "\n  most common cause (1 of 2): boom"
      )
    end
  end
end
