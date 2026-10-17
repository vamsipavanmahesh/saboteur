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

  # #300: removing the cache dir while a run is in flight must not break the
  # run. Every phase that writes optional state recreates the directory
  # (mkdir_p) or keeps writing to its already-open log, so the run finishes
  # with its verdicts and report intact; only rebuildable state (the coverage
  # cache, the in-flight baseline log) is lost. This probe removes the
  # directory at a controlled point - after startup, while the baseline suite
  # is held open by a sync spec - and pins that recovery. A control run pins
  # the exit code and verdicts the probe run must match.
  it "recovers when the cache dir is removed mid-run" do
    marker = File.join(dir, "sync-marker")
    release = File.join(dir, "sync-release")
    write_sync_spec(dir, marker, release)

    control = saboteur(copy_fixture("people"), "--all")

    env = { "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }
    command = [RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE, "run", "--all"]
    Open3.popen3(env, *command, chdir: dir) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      # Drain both pipes so the child never blocks on a full buffer.
      Thread.new { stdout.read }
      err_reader = Thread.new { stderr.read }

      await_marker(marker, wait_thr, err_reader)
      cache = File.join(dir, ".saboteur")
      expect(File.directory?(cache)).to be(true)

      FileUtils.rm_rf(cache)
      File.write(release, "go")

      unless wait_thr.join(120)
        Process.kill("KILL", wait_thr.pid)
        flunk "the run did not finish after the cache dir was removed: #{err_reader.value}"
      end
      status = wait_thr.value.exitstatus
      err = err_reader.value

      # The exit code still belongs to the results: the same survivor-driven
      # exit as the untouched control run, with no test blamed for the
      # missing directory.
      expect(status).to eq(control.status)
      expect(err).not_to include("killing test")

      # Required evidence is recreated: the report holds the same verdicts
      # as the control run.
      report = File.join(cache, "report.json")
      expect(File).to exist(report)
      expect(verdicts(report)).to eq(verdicts(File.join(control.dir, ".saboteur", "report.json")))

      # The baseline log is the only state lost: it is written before the
      # removal and only diagnoses a failed baseline. Every later phase
      # recreates its own optional state - the coverage map and preview are
      # built after the baseline, so they land in the recreated directory.
      expect(File).not_to exist(File.join(cache, "baseline-1.log"))
      expect(Dir.glob(File.join(cache, "coverage-*.json"))).not_to be_empty
      expect(File).to exist(File.join(cache, "preview.json"))
    end
  end

  # A spec file added to the copied fixture. It holds the baseline open at a
  # known point - the baseline log exists, so startup is done - until the
  # probe releases it. The marker and release files live outside the cache
  # dir, so they survive the removal and every later phase passes straight
  # through. The deadline turns a stuck probe into a failed example instead
  # of a hung suite.
  def write_sync_spec(dir, marker, release)
    File.write(File.join(dir, "spec", "sync_spec.rb"), <<~RUBY)
      RSpec.describe "cache probe sync" do
        it "waits for the probe once" do
          marker = #{marker.inspect}
          release = #{release.inspect}
          if !File.exist?(marker) && File.exist?(File.join(Dir.pwd, ".saboteur", "baseline-1.log"))
            File.write(marker, "baseline is running")
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
            until File.exist?(release)
              raise "the probe never released the run" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

              sleep 0.05
            end
          end
        end
      end
    RUBY
  end

  # Fails fast, with the run's stderr, when the run exits before the sync
  # point or never reaches it. join(0.05) doubles as the poll interval.
  def await_marker(marker, wait_thr, err_reader)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
    until File.exist?(marker)
      flunk "the run exited before the sync point: #{err_reader.value}" if wait_thr.join(0.05)
      raise "the run never reached the sync point" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end

  # { mutant id => status } for every mutant in a report, so a verdict
  # comparison is insensitive to file and mutant ordering.
  def verdicts(report_path)
    report = JSON.parse(File.read(report_path, encoding: "UTF-8"))
    report.fetch("files").values.flat_map { |file| file.fetch("mutants") }
          .to_h { |mutant| [mutant.fetch("id"), mutant.fetch("status")] }
  end
end
