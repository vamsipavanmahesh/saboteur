# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::SafeOut do
  let(:io) { StringIO.new }
  let(:out) { described_class.new(io) }

  it "breaks a CI workflow command that starts a line, also after an injected newline" do
    out.puts "spec/a.rb\n::error::injected"
    out.puts "##[error]azure"
    expect(io.string).to eq("spec/a.rb\n\\x3a:error::injected\n##\\x5berror]azure\n")
  end

  it "escapes control characters that would move the cursor or end a line early" do
    out.puts "a\r\e[2Jb\0"
    expect(io.string).to eq("a\\x0d\\x1b[2Jb\\x00\n")
  end

  it "keeps our own colour codes and ordinary text" do
    out.puts "\e[31mred\e[0m Saboteur::Error [1]: ok"
    expect(io.string).to eq("\e[31mred\e[0m Saboteur::Error [1]: ok\n")
  end

  it "does not let a tab hide a command from the guard" do
    out.puts "a\n\t::error::x"
    out.puts " \t ::error::y"
    expect(io.string).to eq("a\n\\x09::error::x\n \\x09 ::error::y\n")
    expect(io.string.lines.map(&:lstrip)).to all(satisfy { |line| !line.start_with?("::") })
  end

  it "escapes colour codes that Palette never writes" do
    out.puts "\e[8mhidden\e[30;40mblack\e[31;9mx"
    expect(io.string).to eq("\\x1b[8mhidden\\x1b[30;40mblack\\x1b[31;9mx\n")
  end

  it "keeps the combined sequences Palette writes for one token" do
    out.puts "\e[31;1m-\e[0m"
    expect(io.string).to eq("\e[31;1m-\e[0m\n")
  end

  it "does not let colour codes hide a command at the start of the text" do
    out.puts "\e[31m::error::x\e[0m"
    expect(io.string).to eq("\e[31m\\x3a:error::x\e[0m\n")
  end

  it "prints a bare newline for no argument and flattens arrays like IO#puts" do
    out.puts
    out.puts ["a", nil, "b"]
    expect(io.string).to eq("\na\n\nb\n")
  end

  it "keeps blank lines: a trailing pair, a leading empty line and a lone newline" do
    out.puts "a\n\n"
    out.puts "\nx"
    out.puts "\n"
    expect(io.string).to eq("a\n\n\nx\n\n")
  end

  it "escapes a carriage return before a line break" do
    out.puts "a\r\n::error::b"
    expect(io.string).to eq("a\\x0d\n\\x3a:error::b\n")
  end

  it "passes everything else through to the wrapped output" do
    expect(out.tty?).to be(false)
    out.print("x")
    expect(io.string).to eq("x")
  end
end
