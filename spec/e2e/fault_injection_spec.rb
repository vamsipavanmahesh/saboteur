# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Fault-injection tests of the tool itself (#251): saboteur must fail
# without blaming a test - exit 3 for a tool failure, exit 5 when the
# hostile condition fails the baseline guard - a message naming the
# hostile condition - when its own environment breaks. Locale and non-ASCII paths work since
# #231/#232, so utf8_locale_spec pins them functionally instead of as
# failures; destructive mutants are pinned by hazard_guard_spec; the
# supervisor and runner specs own the containment unit tests. This group
# owns the cache and log faults plus the end-to-end killed-worker probe.
# Each probe runs against a copy of the people fixture, so the injected
# damage never touches the repository.
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

  # #411: a spec that calls exit at load makes rspec-core set the quit flag
  # and re-raise SystemExit. The run must refuse - exit 3 with the refusal
  # on stderr and rspec's wording naming the file on stdout - never adopt
  # the spec's own status: exit(0) would pass CI without mutating anything.
  it "refuses the run when a spec file calls exit at load" do
    File.write(File.join(dir, "spec", "exit_spec.rb"), "exit(0)\n")

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    expect(run.err).to include("called exit while loading")
    expect(run.out).to include("exit_spec.rb")
  end

  it "exits 5 and names the cache dir when it is read-only" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)

    begin
      FileUtils.chmod(0o555, cache)
      skip "write permission cannot be revoked here (root or capabilities)" if writable?(cache)

      run = saboteur(dir, "--all")

      expect(run.status).to eq(5)
      expect(run.err).to include("Permission denied", ".saboteur", "No mutants were started")
      expect(run.err).not_to include("killing test")
    ensure
      # Restore before fixture cleanup: a 0555 cache dir would survive it.
      FileUtils.chmod(0o755, cache)
    end
  end

  it "exits 5 and names the path when the cache dir is a regular file" do
    File.write(File.join(dir, ".saboteur"), "not a directory")

    run = saboteur(dir, "--all")

    expect(run.status).to eq(5)
    # The failure must name the cache path and its non-directory state; the
    # exact errno wording varies by platform.
    expect(run.err).to match(/\.saboteur/)
    expect(run.err).to match(/exists|directory/i)
    expect(run.err).to include("No mutants were started")
    expect(run.err).not_to include("killing test")
  end

  it "exits 5 and names the log when the baseline log is not writable" do
    cache = File.join(dir, ".saboteur")
    FileUtils.mkdir_p(cache)
    log = File.join(cache, "baseline-1.log")
    File.write(log, "")

    begin
      FileUtils.chmod(0o400, log)
      skip "write permission cannot be revoked here (root or capabilities)" if writable_file?(log)

      run = saboteur(dir, "--all")

      expect(run.status).to eq(5)
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
    # pgroup: the run gets its own process group, so cleanup kills can never
    # reach the suite's own group. The run's children may form groups of
    # their own; cleanup_run walks the tree and kills each group it finds.
    # The err buffer lets a failure message quote stderr without a blocking
    # read of a live pipe.
    Open3.popen3(env, *command, chdir: dir, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      err = +""
      err_lock = Mutex.new
      # Drain both pipes so the child never blocks on a full buffer; the
      # handles stay around so cleanup can join and, when stuck, close them.
      readers = [
        [Thread.new { stdout.read }, stdout],
        [Thread.new { stderr.each_line { |line| err_lock.synchronize { err << line } } }, stderr]
      ]
      begin
        stdin.close

        await_marker(marker, wait_thr, err, err_lock)
        cache = File.join(dir, ".saboteur")
        expect(File.directory?(cache)).to be(true)

        FileUtils.rm_rf(cache)
        File.write(release, "go")

        finished = wait_thr.join(120)
        expect(finished).not_to be_nil, "the run did not finish: #{err_lock.synchronize { err.dup }}"
        readers.each { |reader,| reader.join(5) }
        expect(wait_thr.value.exitstatus).to eq(control.status)
        # No test is blamed for the missing directory.
        expect(err).not_to include("killing test")

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
        cleanup_run(wait_thr, readers)
      end
    end
  end

  # #251: a worker killed from outside (the OOM killer, a user with
  # kill -9) is an environment failure, not a failing test: exit 3, the
  # message names the signal, and nothing blames the suite's tests. The
  # kill lands in the mutation phase - the deepest point at which the pool
  # can lose a worker - and pgroup plus cleanup_run follow the
  # baseline-window probe's discipline, so a failing probe never leaks the
  # process tree into CI.
  it "exits 3 and names the signal when a worker is killed in the mutation phase" do
    env = { "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }
    command = [RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE, "run", "--all", "--jobs", "2"]
    Open3.popen3(env, *command, chdir: dir, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      err = +""
      err_lock = Mutex.new
      # Drain both pipes on threads: a sequential read can deadlock on a
      # full stderr buffer, and the handles stay around for cleanup.
      readers = [
        [Thread.new { stdout.read }, stdout],
        [Thread.new { stderr.each_line { |line| err_lock.synchronize { err << line } } }, stderr]
      ]
      begin
        stdin.close
        killed = false
        killer = Thread.new do
          # The progress header marks the mutation phase; killing earlier
          # would only re-cover the baseline-child path.
          sleep 0.02 until err_lock.synchronize { err.include?(": progress") } || wait_thr.join(0)
          until wait_thr.join(0.05)
            `pgrep -P #{wait_thr.pid}`.lines.map(&:to_i).each do |child|
              Process.kill("KILL", child)
              killed = true
            rescue Errno::ESRCH
              nil
            end
          end
        end
        finished = wait_thr.join(180)
        expect(finished).not_to be_nil, "the run did not finish: #{err_lock.synchronize { err.dup }}"
        killer.join
        readers.each { |reader,| reader.join(5) }
        expect(killed).to be(true) # the probe really killed a worker
        expect(wait_thr.value.exitstatus).to eq(3)
        expect(err).to include("signal KILL")
        expect(err).not_to include("killing test")
      ensure
        cleanup_run(wait_thr, readers)
      end
    end
  end

  # A spec file added to the copied fixture. It holds the baseline open at a
  # known point - the baseline log exists, so startup is done - until the
  # probe releases it. The marker and release files live outside the cache
  # dir, so they survive the removal and every later phase passes straight
  # through. The deadline turns a stuck probe into a failed example instead
  # of a hung suite.
  # #378: an engine-style repo keeps an embedded dummy app under spec/dummy
  # whose specs load a Rails env the parent process does not have. Loading
  # the whole spec tree then dies at setup. The tool error must name the
  # files that failed to load and the way out, or a new user is stuck.
  it "names the failed files and the way out when spec files crash at load" do
    dummy = File.join(dir, "spec", "dummy", "spec")
    FileUtils.mkdir_p(dummy)
    File.write(File.join(dummy, "broken_spec.rb"), <<~RUBY)
      require "rails_helper"

      RSpec.describe "dummy app" do
        it("works") { expect(1).to eq(1) }
      end
    RUBY

    run = saboteur(dir, "--all")

    expect(run.status).to eq(3)
    expect(run.err).to include("spec/dummy/spec/broken_spec.rb")
    expect(run.err).to include("--exclude-pattern", "rspec_args")
    expect(run.err).not_to include("killing test")
  end

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

  # Bounded cleanup for a probe run: kill the whole tree, reap the leader,
  # then join each reader with a bound, closing its pipe when a stuck reader
  # is the only thing holding it open. Nothing here may hang the suite.
  def cleanup_run(wait_thr, readers)
    kill_tree(wait_thr.pid)
    wait_thr.join(5)
    readers.each do |reader, io|
      next if reader.join(5)

      begin
        io.close unless io.closed?
      rescue IOError, SystemCallError
        nil
      end
      reader.join(5)
    end
  end

  # Kills the leader's group and every descendant group found below it:
  # supervisor and worker children move into groups of their own, so one
  # group kill never reaches them, and a descendant that never formed one
  # still shares the leader's group after the leader exits. The descendant
  # scan runs before the kills, while the parent links are intact. ESRCH
  # means that group is already gone; EPERM means we may not signal it.
  def kill_tree(pid)
    (descendant_pgroups(pid) + [pid]).uniq.each do |pgid|
      Process.kill("KILL", -pgid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end

  # Process group ids below the leader: ps lists pid, ppid and pgid per
  # process, and the parent links are walked down from the leader.
  def descendant_pgroups(pid)
    rows = `ps -eo pid=,ppid=,pgid=`.lines.map { |line| line.split.map(&:to_i) }
    by_parent = rows.group_by { |(_, ppid, _)| ppid }
    queue = [pid]
    pgids = []
    until queue.empty?
      (by_parent.delete(queue.shift) || []).each do |(child_pid, _, pgid)|
        pgids << pgid
        queue << child_pid
      end
    end
    pgids
  end

  # { mutant id => status } for every mutant in a report, so a verdict
  # comparison is insensitive to file and mutant ordering.
  def verdicts(report_path)
    report = JSON.parse(File.read(report_path, encoding: "UTF-8"))
    report.fetch("files").values.flat_map { |file| file.fetch("mutants") }
          .to_h { |mutant| [mutant.fetch("id"), mutant.fetch("status")] }
  end
end
