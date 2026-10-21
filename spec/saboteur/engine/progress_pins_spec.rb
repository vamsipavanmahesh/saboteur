# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Golden progress contract (DX wave 1, PR5 slice A): one dim legend at
# start, glyph chunks that fit the terminal with a dim count suffix on
# every commit, and one redrawing status line on a TTY.
RSpec.describe Saboteur::Engine::Diagnostics, "progress pins" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }
  let(:killed) { Struct.new(:status).new(:killed) }
  let(:survived) { Struct.new(:status).new(:survived) }
  let(:timeout) { Struct.new(:status).new(:timeout) }
  let(:error) { Struct.new(:status).new(:error) }

  def run_marks(results, total: results.size, diag: diagnostics)
    diag.start_progress(total)
    results.each { |result| diag.progress(result) }
    diag.finish_progress
    err.string
  end

  it "prints the dim legend once at run start, on pipes and terminals" do
    text = run_marks([killed])
    expect(text).to start_with(".:killed S:survived T:timeout E:error s:skipped L:resource limit\n")

    tty = StringIO.new
    allow(tty).to receive(:tty?).and_return(true)
    on_tty = described_class.new(tty)
    on_tty.start_progress(1)
    expect(tty.string).to include(".:killed S:survived T:timeout E:error s:skipped L:resource limit")
    on_tty.finish_progress
  end

  it "chunks the glyph stream to the terminal width minus the suffix room, floored at 40" do
    allow(err).to receive(:winsize).and_return([24, 200])
    text = run_marks(Array.new(400, killed), total: 400)
    chunk_lines = text.lines.select { |line| line.start_with?(".") && line.include?("(") }
    expect(chunk_lines.size).to eq(3)
    expect(chunk_lines.first).to start_with("." * 190)
    expect(chunk_lines.last).to start_with("." * 20)
    chunk_lines.each { |line| expect(line).to match(%r{  \d+/400 \(\d+%\)}) }
  end

  it "never chunks below 40 glyphs even on a narrow terminal" do
    allow(err).to receive(:winsize).and_return([24, 30])
    text = run_marks(Array.new(90, killed), total: 90)
    chunk_lines = text.lines.grep(%r{\A\.+  \d+/})
    expect(chunk_lines.first).to start_with("." * 40)
  end

  it "redraws exactly one status line on a TTY and commits chunks with a newline" do
    allow(err).to receive(:tty?).and_return(true)
    allow(err).to receive(:winsize).and_return([24, 60])
    quiet = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: false))
    text = run_marks(Array.new(5, killed), total: 5, diag: quiet)
    expect(text.scan("\r\e[K").size).to be >= 5
    expect(text).not_to include("\n.", "S\n")
    # No newline between the legend and the final commit: one redrawing line.
    expect(text.count("\n")).to eq(2)
    expect(text).to end_with(".....  5/5 (100%)\n")
  end

  it "never emits a redraw on a pipe" do
    diagnostics.start_progress(200)
    40.times { diagnostics.progress(killed) }
    expect(err.string).not_to include("(")
    diagnostics.finish_progress
    expect(err.string).not_to include("\r", "\e[K")
  end

  it "paints S bold red, T yellow, E and L red and the dots dim when colour is forced" do
    loud = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: true))
    loud.start_progress(5)
    [killed, survived, timeout, error, Struct.new(:status).new(:resource_limit)].each { |r| loud.progress(r) }
    loud.finish_progress
    text = err.string
    expect(text).to include("\e[2m.:killed S:survived T:timeout E:error s:skipped L:resource limit\e[0m")
    expect(text).to include("\e[2m.\e[0m", "\e[31;1mS\e[0m", "\e[33mT\e[0m", "\e[31;1mE\e[0m", "\e[31;1mL\e[0m")
  end

  it "emits zero ESC bytes in monochrome, forced or auto-detected" do
    expect(run_marks([killed, survived, timeout, error])).not_to include("\e")
    plain = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: false))
    expect(run_marks([killed, survived], diag: plain)).not_to include("\e")
  end

  it "chunks to 70 glyphs when the output has no winsize" do
    text = run_marks(Array.new(80, killed), total: 80)
    chunk_lines = text.lines.grep(%r{\A\.+  \d+/})
    expect(chunk_lines.first).to start_with("." * 70)
  end

  it "ends a partial chunk with a newline and unlinks the progress file" do
    diagnostics.start_progress(10)
    3.times { diagnostics.progress(killed) }
    file = diagnostics.instance_variable_get(:@progress_file)
    before = err.string.dup
    diagnostics.finish_progress
    expect(err.string).to start_with(before)
    expect(err.string.delete_prefix(before)).to end_with("\n")
    expect(file.path).to be_nil
    expect(diagnostics.instance_variable_get(:@progress_file)).to be_nil
  end

  it "adds nothing after an exact full chunk" do
    allow(err).to receive(:winsize).and_return([24, 60])
    diagnostics.start_progress(50)
    50.times { diagnostics.progress(killed) }
    before = err.string.dup
    diagnostics.finish_progress
    expect(err.string).to eq(before)
  end

  it "prints nothing when progress never started" do
    diagnostics.finish_progress
    expect(err.string).to eq("")
  end

  it "keeps its count in a binary, unbuffered file named for saboteur" do
    diagnostics.start_progress(5)
    file = diagnostics.instance_variable_get(:@progress_file)
    expect(File.basename(file.path)).to start_with("saboteur-progress")
    expect(file.sync).to be(true)
    expect(file.external_encoding).to eq(Encoding::BINARY)
    diagnostics.finish_progress
  end

  it "does not need an output that answers tty? or winsize" do
    plain = Class.new do
      attr_reader :text

      def initialize = @text = +""
      def puts(*lines) = @text << lines.join("\n") << "\n"
      def print(*parts) = @text << parts.join
      def flush; end
    end.new
    quiet = described_class.new(plain)
    quiet.start_progress(2)
    quiet.progress(killed)
    quiet.finish_progress
    expect(plain.text).to include(".:killed", ".  1/2")
    expect(plain.text).not_to include("\r", "\e")
  end

  it "marks a status it has no glyph for with a question mark" do
    diagnostics.start_progress(5)
    diagnostics.progress(Struct.new(:status).new(:mystery))
    diagnostics.finish_progress
    expect(err.string).to include("?  1/5")
  end

  it "still prints a bare mark per result when no run announced a total" do
    diagnostics.progress(killed)
    expect(err.string).to eq(".")
  end

  it "pins the exact TTY redraw stream and its final commit" do
    allow(err).to receive(:tty?).and_return(true)
    allow(err).to receive(:winsize).and_return([24, 50])
    allow(Process).to receive(:clock_gettime).and_return(0.0)
    diag = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: false))
    diag.start_progress(5)
    3.times { diag.progress(killed) }
    diag.finish_progress
    expect(err.string).to eq("#{<<~TEXT.chomp}\n")
      .:killed S:survived T:timeout E:error s:skipped L:resource limit
      \r\e[K.  1/5 (20%) eta 0m00s\r\e[K..  2/5 (40%) eta 0m00s\r\e[K...  3/5 (60%) eta 0m00s\r\e[K...  3/5 (60%) eta 0m00s
    TEXT
  end

  it "clears the glyph buffer between piped chunks" do
    allow(Process).to receive(:clock_gettime).and_return(0.0)
    diagnostics.start_progress(75)
    75.times { diagnostics.progress(killed) }
    diagnostics.finish_progress
    expect(err.string).to eq(<<~TEXT)
      .:killed S:survived T:timeout E:error s:skipped L:resource limit
      #{'.' * 70}  70/75 (93%) eta 0m00s
      .....  75/75 (100%)
    TEXT
  end

  it "commits a TTY chunk at exactly the chunk width, then keeps redrawing" do
    allow(err).to receive(:tty?).and_return(true)
    allow(err).to receive(:winsize).and_return([24, 50])
    allow(Process).to receive(:clock_gettime).and_return(0.0)
    diag = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: false))
    diag.start_progress(45)
    45.times { diag.progress(killed) }
    diag.finish_progress
    text = err.string
    expect(text).to include("\r\e[K#{'.' * 40}  40/45 (88%) eta 0m00s\n")
    expect(text.count("\n")).to eq(3)
    expect(text).to end_with("\r\e[K.....  45/45 (100%)\n")
  end

  it "commits when a shrinking terminal leaves the open line wider than the new chunk width" do
    allow(err).to receive(:tty?).and_return(true)
    size = [24, 60]
    allow(err).to receive(:winsize) { size }
    allow(Process).to receive(:clock_gettime).and_return(0.0)
    diag = described_class.new(err, palette: Saboteur::Reporter::Palette.new(enabled: false))
    diag.start_progress(46)
    45.times { diag.progress(killed) }
    size.replace([24, 50])
    diag.progress(killed)
    diag.finish_progress
    expect(err.string).to include("#{'.' * 46}  46/46 (100%)\n")
  end

  it "falls back to the default width when winsize raises" do
    allow(err).to receive(:winsize).and_raise(Errno::ENOTTY)
    text = run_marks(Array.new(75, killed), total: 75)
    chunk_lines = text.lines.grep(%r{\A\.+ {2}\d+/})
    expect(chunk_lines.first).to start_with("." * 70)
  end

  it "reads a later chunk's glyphs from the progress file, not from its head" do
    marks = Array.new(70, killed) + Array.new(5, survived)
    text = run_marks(marks, total: 75)
    expect(text).to include("SSSSS  75/75")
    expect(text).to include("#{'.' * 70}  70/75")
  end

  it "never prints bytes a mutant child wrote to the inherited progress fd" do
    diagnostics.start_progress(5)
    diagnostics.progress(killed)
    diagnostics.instance_variable_get(:@progress_file).write("\e[2J\e[31mBOOM")
    diagnostics.finish_progress
    # The forged bytes pad the count, but none of them come back out.
    expect(err.string).to match(%r{\n\. {2}14/5 })
    expect(err.string).not_to include("BOOM", "\e[2J")
    expect(err.string.bytes).not_to include(0x1b)
  end
end
