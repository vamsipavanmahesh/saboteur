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

  # #300: removing the cache dir during the BASELINE window must not break
  # the run. At that point every later phase (coverage map, mutant logs,
  # reports) still recreates the directory with mkdir_p, and the baseline
  # child keeps writing to its already-open log. Only this window is pinned:
  # a removal while mutant logs are written fails the run by design
  # (Runner#open_log and the vanished-log check), so stop the run before
  # deleting the cache. The probe removes the directory at a controlled
  # point - the baseline log exists, so startup is done and the suite is
  # held open by a sync spec - and pins the recovery. A control run with the
  # identical fixture (its sync spec released up front) pins the exit code
  # and the verdicts the probe run must match.
  it "recovers when the cache dir is removed during the baseline window" do
    marker = File.join(dir, "sync-marker")
    release = File.join(dir, "sync-release")
    write_sync_spec(dir, marker, release)

    control_dir = copy_fixture("people")
    write_sync_spec(control_dir, File.join(control_dir, "sync-marker"), File.join(control_dir, "sync-release"))
    # Released up front, the control's sync spec passes straight through, so
    # the control runs the identical suite without ever blocking.
    File.write(File.join(control_dir, "sync-release"), "go")
    control = saboteur(control_dir, "--all")
    expect(control.status).to eq(1), control.err
    control_verdicts = verdicts(File.join(control.dir, ".saboteur", "report.json"))
    expect(control_verdicts).not_to be_empty

    env = { "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }
    command = [RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE, "run", "--all"]
    # pgroup: the run forks baseline and mutant children, and cleanup must
    # reach the whole tree, not only the top process. The err buffer lets a
    # failure message quote stderr without a blocking read of a live pipe.
    Open3.popen3(env, *command, chdir: dir, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      err = +""
      err_lock = Mutex.new
      begin
        stdin.close
        Thread.new { stdout.read }
        Thread.new { stderr.each_line { |line| err_lock.synchronize { err << line } } }

        await_marker(marker, wait_thr, err, err_lock)
        cache = File.join(dir, ".saboteur")
        expect(File.directory?(cache)).to be(true)

        FileUtils.rm_rf(cache)
        File.write(release, "go")

        finished = wait_thr.join(120)
        expect(finished).not_to be_nil, "the run did not finish: #{err_lock.synchronize { err.dup }}"
        expect(wait_thr.value.exitstatus).to eq(control.status)

        # Required evidence is recreated: the report holds the same verdicts
        # as the control run.
        report = File.join(cache, "report.json")
        expect(File).to exist(report)
        expect(verdicts(report)).to eq(control_verdicts)

        # The baseline log is the only state lost: it is written before the
        # removal and only diagnoses a failed baseline. Every later phase
        # recreates its own optional state - the coverage map and preview are
        # built after the baseline, so they land in the recreated directory.
        expect(File).not_to exist(File.join(cache, "baseline-1.log"))
        expect(Dir.glob(File.join(cache, "coverage-*.json"))).not_to be_empty
        expect(File).to exist(File.join(cache, "preview.json"))
      ensure
        cleanup_run(wait_thr)
      end
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

  # Fails fast when the run exits before the sync point or never reaches
  # it. join(0.05) doubles as the poll interval; the message quotes the
  # stderr buffered so far, never a blocking read of the live pipe.
  def await_marker(marker, wait_thr, err, err_lock)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
    until File.exist?(marker)
      flunk "the run exited before the sync point: #{err_lock.synchronize { err.dup }}" if wait_thr.join(0.05)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "the run never reached the sync point: #{err_lock.synchronize { err.dup }}"
      end
    end
  end

  # Bounded cleanup for a probe run: kill the run's whole process group (the
  # run forks baseline and mutant children of its own), then wait for the
  # exit to be reaped. ESRCH/EPERM mean the group is already gone; a still
  # stuck wait gives up instead of hanging the suite.
  def cleanup_run(wait_thr)
    Process.kill("KILL", -wait_thr.pid) unless wait_thr.join(1)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  ensure
    wait_thr.join(5)
  end

  # { mutant id => status } for every mutant in a report, so a verdict
  # comparison is insensitive to file and mutant ordering.
  def verdicts(report_path)
    report = JSON.parse(File.read(report_path, encoding: "UTF-8"))
    report.fetch("files").values.flat_map { |file| file.fetch("mutants") }
          .to_h { |mutant| [mutant.fetch("id"), mutant.fetch("status")] }
  end
end
