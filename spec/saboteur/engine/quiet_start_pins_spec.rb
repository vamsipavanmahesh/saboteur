# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Noise diet (PR4): the default run opens with three quiet lines - the
# dim run header, the baseline+coverage summary, the dim spec-inference
# summary - and every line it replaces stays available under --verbose,
# byte-for-byte.
RSpec.describe "the quiet run start (DX wave 1, PR4)" do
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

  let(:err) { StringIO.new }
  let(:mono) { Saboteur::Reporter::Palette.new(enabled: false) }
  let(:colour) { Saboteur::Reporter::Palette.new(enabled: true) }

  def diagnostics(palette, verbose: false)
    Saboteur::Engine::Diagnostics.new(err, verbose: verbose, palette: palette)
  end

  # --quiet (#1149): the heartbeat exists outside quiet runs and collapses
  # to the NULL no-op only under it; --verbose detail chatter stays
  # suppressed under --quiet even though --verbose alone would print it.
  it "returns a real heartbeat unless --quiet, the NULL no-op under it" do
    heartbeat = diagnostics(mono).progress_heartbeat("baseline check 1")
    expect(heartbeat).not_to be(Saboteur::Engine::Diagnostics::ProgressHeartbeat::NULL)
    quiet = Saboteur::Engine::Diagnostics.new(err, palette: mono, quiet: true)
    expect(quiet.progress_heartbeat("baseline check 1"))
      .to be(Saboteur::Engine::Diagnostics::ProgressHeartbeat::NULL)
  end

  it "suppresses --verbose detail chatter under --quiet" do
    d = Saboteur::Engine::Diagnostics.new(err, verbose: true, palette: mono, quiet: true)
    d.detail("checking the unchanged suite twice (seed 1)")
    expect(err.string).to eq("")
  end

  # --quiet (#1149): findings, score line and verdict reach the terminal
  # report; the engine side stays silent - no startup lines, no chatter,
  # no progress rendering, no heartbeat.
  it "suppresses the startup lines, chatter, progress and heartbeat under --quiet" do
    d = Saboteur::Engine::Diagnostics.new(err, palette: mono, quiet: true)
    d.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    d.quiet_baseline(passes: 1, elapsed: 0.4, tests: 6, cached: false)
    d.quiet_inference(2)
    d.detail("spec discovery chatter")
    d.start_progress(3)
    d.progress(instance_double(Saboteur::MutantResult, status: :killed))
    d.finish_progress
    d.progress_heartbeat("baseline check 1").watch(File::NULL).tick
    expect(err.string).to eq("")
  end

  it "still prints the quiet start and progress without --quiet" do
    d = diagnostics(mono)
    d.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    expect(err.string).to include("saboteur #{Saboteur::VERSION}")
  end

  it "prints the three golden lines in monochrome" do
    d = diagnostics(mono)
    d.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    d.quiet_baseline(passes: 2, elapsed: 0.4, tests: 6, cached: true)
    d.quiet_inference(2)
    expect(err.string).to eq("saboteur #{Saboteur::VERSION} · whole project · seed 1 · " \
                             "37 operators (--list-operators)\n" \
                             "✓ baseline green (2 passes, 0.4s)  ✓ coverage map: 6 tests (cached)\n" \
                             "spec inference: 2 spec files (details: --verbose)\n")
  end

  it "paints the same three lines with contract tokens in colour" do
    d = diagnostics(colour)
    d.quiet_start_header(scope: "--since origin/main", seed: 7, operators: 37)
    d.quiet_baseline(passes: 1, elapsed: 12.34, tests: 41, cached: false)
    d.quiet_inference(1)
    expect(err.string).to eq("\e[2msaboteur #{Saboteur::VERSION} · --since origin/main · seed 7 · " \
                             "37 operators (--list-operators)\e[0m\n" \
                             "\e[32m✓\e[0m baseline green (1 pass, 12.3s)  \e[32m✓\e[0m coverage map: 41 tests\n" \
                             "\e[2mspec inference: 1 spec file (details: --verbose)\e[0m\n")
  end

  it "prints none of the quiet lines under --verbose" do
    d = diagnostics(mono, verbose: true)
    d.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    d.quiet_baseline(passes: 2, elapsed: 0.4, tests: 6, cached: true)
    d.quiet_inference(2)
    expect(err.string).to eq("")
  end

  it "keeps demoted chatter verbatim under --verbose and hides it by default" do
    verbose = diagnostics(mono, verbose: true)
    verbose.detail("checking the unchanged suite twice (seed 1)")
    expect(err.string).to eq("saboteur: checking the unchanged suite twice (seed 1)\n")

    err.truncate(0)
    err.rewind
    diagnostics(mono).detail("checking the unchanged suite twice (seed 1)")
    expect(err.string).to eq("")
  end

  it "keeps a demoted announcement in report.warnings without reprinting it" do
    d = diagnostics(mono)
    d.announce_demoted("inferred specs: running only spec/a_spec.rb")
    expect(d.warnings).to eq(["inferred specs: running only spec/a_spec.rb"])
    expect(d.live_announced).to eq(["inferred specs: running only spec/a_spec.rb"])
    expect(err.string).to eq("")
  end
  it "stays silent on the machine path (quiet: false), which keeps --format agent byte-identical" do
    d = Saboteur::Engine::Diagnostics.new(err, verbose: false, palette: mono, quiet_start: false)
    d.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    d.quiet_baseline(passes: 2, elapsed: 0.4, tests: 6, cached: true)
    d.quiet_inference(2)
    expect(err.string).to eq("")
  end
  it "prints demoted chatter on the machine path (quiet_start: false), which keeps --format agent byte-identical" do
    d = Saboteur::Engine::Diagnostics.new(err, verbose: false, palette: mono, quiet_start: false)
    d.detail("checking the unchanged suite twice (seed 1)")
    expect(err.string).to eq("saboteur: checking the unchanged suite twice (seed 1)\n")
  end

  it "singularizes one pass and one test" do
    diagnostics(mono).quiet_baseline(passes: 1, elapsed: 0.1, tests: 1, cached: false)
    expect(err.string).to eq("\u2713 baseline green (1 pass, 0.1s)  \u2713 coverage map: 1 test\n")
  end

  it "says nothing about spec inference when no specs were inferred" do
    diagnostics(mono).quiet_inference(nil)
    expect(err.string).to eq("")
  end
end
