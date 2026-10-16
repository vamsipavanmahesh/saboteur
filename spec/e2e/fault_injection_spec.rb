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

  # chmod is a request, not a guarantee: root and capability-bearing
  # containers can still write a 0555 directory or a 0400 file. Probe the
  # effective ability instead of trusting the mode bits, and skip plainly
  # when the denial cannot be enforced.
  def writable?(path)
    probe = File.join(path, ".write-probe")
    File.write(probe, "x")
    true
  rescue SystemCallError
    false
  ensure
    FileUtils.rm_f(probe)
  end

  # Appending needs real write permission; touching only needs ownership.
  def writable_file?(path)
    File.open(path, "a") { |file| file.write("x") }
    true
  rescue SystemCallError
    false
  end

  it "exits 3 and names the cache dir when it is read-only" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)

    begin
      FileUtils.chmod(0o555, cache)
      skip "write permission cannot be revoked here (root or capabilities)" if writable?(cache)

      run = saboteur(dir, "--all")

      expect(run.status).to eq(3)
      expect(run.err).to include("Permission denied", ".saboteur", "No mutants were started")
      expect(run.err).not_to include("killing test")
    ensure
      # Restore before fixture cleanup: a 0555 cache dir would survive it.
      FileUtils.chmod(0o755, cache)
    end
  end

  it "exits 3 and names the path when the cache dir is a regular file" do
    File.write(File.join(dir, ".saboteur"), "not a directory")

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    # The failure must name the cache path and its non-directory state; the
    # exact errno wording varies by platform.
    expect(run.err).to match(/\.saboteur/)
    expect(run.err).to match(/exists|directory/i)
    expect(run.err).to include("No mutants were started")
    expect(run.err).not_to include("killing test")
  end

  it "exits 3 and names the log when the baseline log is not writable" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)
    log = File.join(cache, "baseline-1.log")
    File.write(log, "")

    begin
      FileUtils.chmod(0o400, log)
      skip "write permission cannot be revoked here (root or capabilities)" if writable_file?(log)

      run = saboteur(dir, "--all")

      expect(run.status).to eq(3)
      expect(run.err).to include("Permission denied", "baseline-1.log", "No mutants were started")
      expect(run.err).not_to include("killing test")
    ensure
      FileUtils.chmod(0o600, log)
    end
  end
end
