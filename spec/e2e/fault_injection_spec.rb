# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Fault-injection tests of the tool itself (#251): saboteur must fail as a
# tool - exit 3, a message naming the hostile condition, no test blamed -
# when its own environment breaks. Locale, killed-child and destructive-
# mutant faults are pinned elsewhere (utf8_locale_spec, the supervisor and
# runner specs, hazard_guard_spec); this group owns the cache and log
# faults. Each probe runs against a copy of the people fixture, so the
# injected damage never touches the repository.
RSpec.describe "fault injection: hostile cache and log state", :e2e do
  let(:dir) { copy_fixture("people") }

  it "exits 3 and names the cache dir when it is read-only" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)
    FileUtils.chmod(0o555, cache)

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    expect(run.err).to include("Permission denied", ".saboteur", "No mutants were started")
    expect(run.err).not_to include("killing test")
  end

  it "exits 3 and names the path when the cache dir is a regular file" do
    File.write(File.join(dir, ".saboteur"), "not a directory")

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    expect(run.err).to include(".saboteur", "No mutants were started")
    expect(run.err).not_to include("killing test")
  end

  it "exits 3 and names the log when the baseline log is not writable" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)
    log = File.join(cache, "baseline-1.log")
    File.write(log, "")
    FileUtils.chmod(0o400, log)

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    expect(run.err).to include("Permission denied", "baseline-1.log", "No mutants were started")
    expect(run.err).not_to include("killing test")
  end
end
