# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "the colour contract (DX wave 1, PR1)" do
  # The goldens pin the UTF-8 glyphs; force a UTF-8 locale so a
  # C-locale CI leg does not downgrade them to their ASCII fallbacks.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  let(:out) { StringIO.new }

  def render(report, **options)
    Saboteur::Reporter::Terminal.new(out, **options).call(report)
    out.string
  end

  # One canned run with a kill and a covered survivor: the shape the golden
  # mock tags with tokens (tallies, score band, findings, evidence, command).
  let(:report) do
    report_of(result_for(:killed, runtime: 0.5, killed_by: ["./spec/p_spec.rb[1:1]"]),
              result_for(:survived, covered_by: ["./spec/p_spec.rb[1:1]"]))
  end

  it "writes zero ESC bytes when piped" do
    expect(render(report, color: :never).bytes).not_to include(0x1b)
  end

  it "paints every contract token where the mock tags it under --color=always" do
    # all_mutants: the per-mutant block is where the mock tags the removed
    # and added lines and the dim digest; the collapsed default (#1065) has
    # no per-mutant lines.
    text = render(report, color: :always, threshold: 80, all_mutants: true)
    digest = report.unignored_survivors.first.digest
    # head: structure (the Survivors heading and the finding header).
    expect(text).to include("\e[1mSurvivors (1) - changes your tests did not catch\e[0m",
                            "\n\e[1m1. person.rb:2\e[0m")
    # fail: the survivor tally, the score below the threshold, the removed line.
    expect(text).to include("\e[31;1m1 survived\e[0m", "\e[31;1m50.0%\e[0m",
                            "\e[31;1m-   2 def adult?; @age >= 18; end\e[0m")
    # pass: the killed tally and the added line.
    expect(text).to include("\e[32m1 killed\e[0m", "\e[32m+   2 def adult?; @age > 18; end\e[0m")
    # dim: context (the operator and digest, the covered-by verdict, the
    # why-it-matters line and the tally).
    expect(text).to include("\e[2m   comparison \u00b7 #{digest}\e[0m", "\e[2m- ran, still passed\e[0m")
    expect(text).to include("\e[2mwhy it matters: the boundary between the two comparisons is untested\e[0m",
                            "\e[2msaboteur 0.11.0: 1 subjects, 2 mutants, wall 1.25 s, seed 1 " \
                            "(repeat with --seed 1)\e[0m")
    # info: the paste-able replay command, with its lead-in.
    expect(text).to include("  replay one survivor: \e[36msaboteur run --id #{digest} --seed 1\e[0m")
  end

  it "bands the score pass at or above the threshold" do
    text = render(report_of(result_for(:killed)), color: :always, threshold: 80)
    expect(text).to include("\e[32m100.0%\e[0m")
  end

  it "bands the score fail just below a fractional threshold" do
    results = [">", "<", "<=", "=="].map { |r| result_for(:killed, replacement: r) } + [result_for(:survived)]
    text = render(report_of(*results), color: :always, threshold: 80.5)
    expect(text).to include("Score: \e[31;1m80.0%\e[0m", "\e[31;1m \u00b7 threshold 80.5 (break)\e[0m")
  end

  it "bands the score pass exactly at the threshold, even with a survivor" do
    results = [">", "<", "<=", "=="].map { |r| result_for(:killed, replacement: r) } + [result_for(:survived)]
    expect(render(report_of(*results), color: :always, threshold: 80)).to include("Score: \e[32m80.0%\e[0m")
  end

  it "leaves the score unpainted without a threshold" do
    text = render(report_of(result_for(:killed)), color: :always)
    expect(text).to include("Score: 100.0%")
    expect(text).not_to include("\e[32m100.0%\e[0m")
  end

  it "leaves an unscored run's score unpainted" do
    text = render(report_of, color: :always, threshold: 80)
    expect(text).to include("Score: n/a")
    expect(text).not_to include("\e[32mn/a\e[0m", "\e[31;1mn/a\e[0m")
  end

  it "detects colour per stream: forcing one stream never paints the other" do
    tty = StringIO.new.tap { |io| allow(io).to receive(:tty?).and_return(true) }
    pipe = StringIO.new
    expect(Saboteur::Reporter::Palette.for(pipe, mode: :always, environment: {}).enabled?).to be(true)
    expect(Saboteur::Reporter::Palette.for(pipe, environment: {}).enabled?).to be(false)
    expect(Saboteur::Reporter::Palette.for(tty, environment: {}).enabled?).to be(true)
  end

  it "paints progress marks and the legend through the stderr palette" do
    err = StringIO.new
    palette = Saboteur::Reporter::Palette.for(err, mode: :always)
    diagnostics = Saboteur::Engine::Diagnostics.new(err, verbose: true, palette:)
    diagnostics.start_progress(2)
    report.results.each { |result| diagnostics.progress(result) }
    diagnostics.finish_progress
    expect(err.string).to include("\e[2m#{Saboteur::Engine::Diagnostics::LEGEND}\e[0m")
    expect(err.string).to include("\e[2m.\e[0m", "\e[31;1mS\e[0m")
  end

  it "keeps stderr progress monochrome on a pipe in auto mode" do
    err = StringIO.new
    diagnostics = Saboteur::Engine::Diagnostics.new(err, verbose: true)
    diagnostics.start_progress(1)
    diagnostics.progress(result_for(:survived))
    expect(err.string.bytes).not_to include(0x1b)
  end

  it "paints run warnings with the warn token when colour is on" do
    warned = report_of(result_for(:killed, runtime: 0.5, killed_by: ["./spec/p_spec.rb[1:1]"]),
                       warnings: ["the tree is dirty"])
    expect(render(warned, color: :always)).to include("\e[33mwarning: the tree is dirty\e[0m")
  end

  it "keeps run warnings monochrome when piped" do
    warned = report_of(result_for(:killed, runtime: 0.5, killed_by: ["./spec/p_spec.rb[1:1]"]),
                       warnings: ["the tree is dirty"])
    piped = render(warned)
    expect(piped).to include("warning: the tree is dirty")
    expect(piped.bytes).not_to include(0x1b)
  end

  describe "warning notices" do
    it "paints the fact lines :warn and a Fix: line :dim (the two-line shape)" do
      palette = Saboteur::Reporter::Palette.new(enabled: true)
      expect(Saboteur::Reporter::Notice.paint(palette, "saboteur: warning: tree dirty\nFix: commit first"))
        .to eq("\e[33msaboteur: warning: tree dirty\e[0m\n\e[2mFix: commit first\e[0m")
    end

    it "passes the text through byte-identical when colour is off" do
      text = "saboteur: warning: tree dirty\nFix: commit first"
      expect(Saboteur::Reporter::Notice.paint(Saboteur::Reporter::Palette.new(enabled: false), text)).to eq(text)
    end
  end
end
