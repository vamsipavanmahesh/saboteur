# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::ExternalRunner do
  let(:source) do
    <<~RUBY
      class Calc
        def positive?(n)
          n >= 0
        end
      end
    RUBY
  end

  def subject_in(dir)
    path = File.join(dir, "calc.rb")
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects.first
  end

  def mutation_for(subject)
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                              replacement: "<")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                           coarse: false)
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def run_in(dir, command, timeout: 5, mutation: :real)
    subject = subject_in(dir)
    runner = described_class.new(command: command, root: dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: timeout,
                         mutation: mutation == :real ? mutation_for(subject) : nil)
    [outcome, runner, subject]
  end

  # Functional proof the group is gone: a reaped zombie still answers
  # kill(0), so watch the descendant's tick file stop growing instead.
  def expect_ticks_stopped(path)
    size = File.exist?(path) ? File.size(path) : 0
    sleep 0.5
    expect(File.exist?(path) ? File.size(path) : 0).to eq(size)
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir) and example.run }
  end

  it "reports survived when the command exits 0 with the mutant applied" do
    outcome, = run_in(@dir, "true")
    expect([outcome.status, outcome.executed_ids]).to eq([:survived, ["(test command)"]])
  end

  it "reports killed with the command as the killer when it exits non-zero" do
    outcome, = run_in(@dir, "false")
    expect([outcome.status, outcome.failed_ids]).to eq([:killed, ["(test command)"]])
  end

  it "lets the command see the mutant and never touches the real file" do
    outcome, = run_in(@dir, "grep -q 'n < 0' calc.rb")
    # grep found the mutant text, so the write happened in the copy.
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "leaves the real file alone when the command times out" do
    outcome, = run_in(@dir, "sleep 30", timeout: 0.2)
    expect(outcome.status).to eq(:timeout)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "runs the unchanged copy for the neutral check and does not write" do
    outcome, = run_in(@dir, "grep -q 'n >= 0' calc.rb", mutation: nil)
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # The shell's "cannot run it" exits are setup errors, not kills (#305):
  # the suite did not run.
  it "reads 127 (command not found) as an error, not a kill" do
    outcome, = run_in(@dir, "definitely-not-a-command-xyz")
    expect([outcome.status, outcome.executed_ids]).to eq([:error, []])
  end

  # An error verdict keeps bounded context for the report (#305 DevRel):
  # what the shell said, capped at the capture limit.
  it "carries the command's own output on setup errors" do
    outcome, = run_in(@dir, "definitely-not-a-command-xyz")
    expect(outcome.message).to include("exit 127 - the shell could not run the command")
    expect(outcome.message).to include("definitely-not-a-command-xyz")
    expect(outcome.message.bytesize).to be < described_class::OUTPUT_LIMIT + 200
  end

  it "reads 126 (cannot execute) as an error" do
    outcome, = run_in(@dir, "exit 126")
    expect(outcome.status).to eq(:error)
  end

  it "reads a command killed by a signal as an error" do
    outcome, = run_in(@dir, "kill -TERM $$")
    expect(outcome.status).to eq(:error)
  end

  # Architect probe, taken further by QA/DevRel: a command that destroys
  # the source inside the copy must not poison ANY later execution - every
  # run starts from a pristine copy (#305).
  it "gives every execution a pristine copy after a destructive command" do
    subject = subject_in(@dir)
    runner = described_class.new(command: "rm calc.rb && mkdir calc.rb", root: @dir)
    first = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                       mutation: mutation_for(subject))
    second = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                        mutation: mutation_for(subject))
    # Both runs honestly report the command's exit; the second mutant is
    # written into a fresh copy, not onto the first run's debris.
    expect([first.status, second.status]).to eq(%i[survived survived])
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # The neutral check must see pristine bytes even right after a mutant
  # (#305 QA): kills are never checked against themselves.
  it "runs the neutral check on unchanged bytes after a mutant" do
    subject = subject_in(@dir)
    runner = described_class.new(command: "grep -q 'n >= 0' calc.rb", root: @dir)
    mutant = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                        mutation: mutation_for(subject))
    neutral = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5, mutation: nil)
    # The command detects the mutant (kill), and the neutral run passes
    # because the fresh copy carries the original bytes again.
    expect([mutant.status, neutral.status]).to eq(%i[killed survived])
  end

  # Mutants in one file must not leak into another file's runs (#305 QA).
  it "keeps mutants in one file out of another file's executions" do
    subject = subject_in(@dir)
    File.write(File.join(@dir, "other.rb"), "OTHER = 1
")
    runner = described_class.new(command: "grep -q 'OTHER = 1' other.rb", root: @dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
  end

  # cp_r keeps symlinks; a link escaping the tree would let a write land
  # in the real tree, so the runner refuses it (#305 QA).
  it "refuses a symlink that escapes the tree" do
    subject_in(@dir)
    outside = File.join(@dir, "..", "outside-#{Process.pid}.rb")
    File.write(outside, "x = 1
")
    File.symlink(outside, File.join(@dir, "linked.rb"))
    runner = described_class.new(command: "true", root: @dir)
    expect do
      runner.preflight!(deadline: monotonic_now + 60)
    end.to raise_error(Saboteur::Error, /links outside itself: linked\.rb/)
  ensure
    File.unlink(outside) if outside && File.exist?(outside)
  end

  # Alias identity is preserved: the copy's link is rebuilt RELATIVE, so a
  # require of the alias sees the mutant, not a pristine materialized copy
  # (#305 QA).
  it "rebuilds an internal symlink as a relative link that sees the mutant" do
    subject = subject_in(@dir)
    File.symlink("calc.rb", File.join(@dir, "alias.rb"))
    runner = described_class.new(command: "test -L alias.rb && grep -q 'n < 0' alias.rb", root: @dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
    # The real files are untouched and the real alias is still a symlink.
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
    expect(File.symlink?(File.join(@dir, "alias.rb"))).to be(true)
  end

  # macOS tmp dirs are symlinked (/var -> /private/var): the copy root must
  # be canonicalized before link targets are judged against it, or every
  # internal link looks like an escape (#305 CI).
  it "judges link targets against the canonical copy root" do
    subject = subject_in(@dir)
    File.symlink("calc.rb", File.join(@dir, "alias.rb"))
    real = Dir.mktmpdir("saboteur-external-")
    alias_root = File.join(Dir.mktmpdir, "linked")
    File.symlink(real, alias_root)
    begin
      allow(Dir).to receive(:mktmpdir).and_call_original
      allow(Dir).to receive(:mktmpdir).with("saboteur-external-").and_return(alias_root)
      runner = described_class.new(command: "test -L alias.rb && grep -q 'n < 0' alias.rb", root: @dir)
      outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                           mutation: mutation_for(subject))
      expect(outcome.status).to eq(:survived)
    ensure
      File.unlink(alias_root)
      FileUtils.remove_entry(real)
    end
  end

  # Architect probe: a background write landing after the verdict must not
  # reach the real tree (#305).
  it "contains a background write that lands after the run" do
    command = "(sleep 0.3; printf LATE > calc.rb) & exit 0"
    outcome, = run_in(@dir, command)
    expect(outcome.status).to eq(:survived)
    sleep 0.6
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # Architect probe: SIGINT must take the whole process group down (#305).
  # The ready file is a handshake: the command has started before the
  # interrupt lands (Principal: no startup race).
  it "kills the process group when the run is interrupted" do
    subject_in(@dir)
    ticks = File.join(@dir, "ticks")
    command = "touch #{@dir}/ready; (while :; do echo t >> #{ticks}; sleep 0.1; done) & wait"
    runner = described_class.new(command: command, root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    thread = Thread.new do
      runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 30,
                 mutation: mutation_for(subject))
    end
    100.times do
      break if File.exist?(File.join(@dir, "ready"))

      sleep 0.05
    end
    # The handshake must have happened, or the interrupt tests nothing.
    expect(File.exist?(File.join(@dir, "ready"))).to be(true)
    thread.raise(Interrupt)
    expect { thread.join }.to raise_error(Interrupt)
    expect_ticks_stopped(ticks)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "kills background descendants that outlive the command" do
    subject_in(@dir)
    ticks = File.join(@dir, "ticks")
    command = "(while :; do echo t >> #{ticks}; sleep 0.1; done) & exit 0"
    runner = described_class.new(command: command, root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
    expect_ticks_stopped(ticks)
  end

  it "passes the recursion marker down to the command's environment" do
    outcome, = run_in(@dir, "test \"$SABOTEUR_EXTERNAL_CHILD\" = 1")
    expect(outcome.status).to eq(:survived)
  end

  # The disposable copy must not leak (merger review, #305): close removes
  # it after normal runs and after errors, and stays idempotent.
  describe "#close" do
    it "removes the copy after a normal run" do
      outcome, runner, = run_in(@dir, "true")
      expect(outcome.status).to eq(:survived)
      copy = runner.instance_variable_get(:@copy_root)
      expect(Dir.exist?(copy)).to be(true)
      runner.close
      expect(Dir.exist?(copy)).to be(false)
      expect { runner.close }.not_to raise_error
    end

    it "removes the copy after a mutant run errors" do
      subject = subject_in(@dir)
      runner = described_class.new(command: "rm calc.rb && mkdir calc.rb", root: @dir)
      runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                 mutation: mutation_for(subject))
      outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                           mutation: mutation_for(subject))
      expect(outcome.status).to eq(:survived) # fresh copy: the first run's debris is gone
      copy = runner.instance_variable_get(:@copy_root)
      runner.close
      expect(Dir.exist?(copy)).to be(false)
    end
  end

  # Architect repro: a session-escaped descendant holding stdout keeps EOF
  # open forever; the drain is bounded, so the run finishes near its own
  # time, not the descendant's (#305). Escaped sessions are not contained.
  # Process.setsid in Ruby, not the setsid utility: macOS has no setsid(1).
  it "does not wait out a session-escaped descendant holding stdout" do
    mark = File.join(@dir, "escaped-ran")
    ruby = RbConfig.ruby
    # The parent waits for the child's marker - written AFTER setsid - so
    # the escape lands before the group TERM: an escapee killed during boot
    # proves nothing, and a fixed sleep is flaky (#305 Principal).
    # --disable-gems: the escapee needs no rubygems, and a gem-loaded boot
    # is the dominant, CI-variable term in this budget (seconds on a loaded
    # macOS runner, where it pushed a 2s threshold to 2.4s). The escapee
    # sleeps 10s and the budget is 5s: waiting it out still fails by 2x,
    # while a slow runner's boot plus the 0.5s drain grace fits easily.
    command = "#{ruby} --disable-gems -e 'Process.setsid; File.write(ARGV[0], \"1\"); sleep 10' #{mark} & " \
              "until [ -f #{mark} ]; do sleep 0.02; done; exit 0"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome, = run_in(@dir, command, timeout: 15)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(outcome.status).to eq(:survived)
    expect(elapsed).to be < 5.0
    # The descendant really escaped and ran, or the drain tests nothing.
    expect(File.exist?(mark)).to be(true)
  end

  # A subject outside the root is refused, never joined onto the copy
  # (#305 QA): no absolute path, no `..` traversal.
  it "refuses a subject file outside the project root" do
    subject_in(@dir)
    outside = File.join(@dir, "..", "escape-#{Process.pid}.rb")
    File.write(outside, source)
    escaped = Saboteur::SubjectFinder.new.call(File.realpath(outside)).subjects.first
    runner = described_class.new(command: "true", root: @dir)
    outcome = runner.run(subject: escaped, text: escaped.source, test_ids: [], timeout: 5,
                         mutation: nil)
    expect(outcome.status).to eq(:error)
    expect(outcome.message).to match(/outside the project root/)
    expect(File.read(File.realpath(outside))).to eq(source)
  ensure
    File.unlink(outside) if outside && File.exist?(outside)
  end

  # Captured bytes land in report JSON: invalid UTF-8 is dropped, not
  # carried raw (#305 Principal).
  it "scrubs invalid UTF-8 from captured output" do
    subject_in(@dir)
    runner = described_class.new(command: "printf 'ok \\303\\050 end'; exit 1", root: @dir)
    expect { runner.preflight!(deadline: monotonic_now + 60) }.to raise_error(Saboteur::Error) do |error|
      expect(error.message).to include("ok ( end")
      expect(error.message.encoding).to eq(Encoding::UTF_8)
      expect(error.message.valid_encoding?).to be(true)
    end
  end

  # Copy/write failures become an error Outcome with context, never a
  # raised crash of the run (#305 QA). Injected, not chmod-based: root
  # ignores permission bits, so a chmod probe is not portable (#305
  # Architect, same lesson as #303).
  it "reports a copy failure as an error outcome with context" do
    subject = subject_in(@dir)
    allow(FileUtils).to receive(:cp_r).and_raise(Errno::EACCES, "denied")
    runner = described_class.new(command: "true", root: @dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:error)
    expect(outcome.message).to match(/denied/)
  end

  # A wait cut short when the overall run budget is also spent is a budget
  # stop, not a command failure (#305 QA); without the budget, the same
  # timeout stays the command's own error.
  it "raises BudgetPhaseTimeout when the run budget cuts the preflight wait" do
    subject_in(@dir)
    runner = described_class.new(command: "sleep 30", root: @dir)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { runner.preflight!(deadline: now + 0.3, budget_deadline: now + 0.1) }
      .to raise_error(Saboteur::BudgetPhaseTimeout, /budget stopped the external preflight/)
    expect { runner.preflight!(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.1) }
      .to raise_error(Saboteur::Error, /timed out/)
  end

  # The budget is admitted AFTER the copy: a deadline already spent is a
  # budget stop only when the budget is the limiting deadline (#305
  # Architect, Principal).
  it "raises BudgetPhaseTimeout when the preflight deadline is already spent" do
    subject_in(@dir)
    runner = described_class.new(command: "true", root: @dir)
    spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1
    expect { runner.preflight!(deadline: spent, budget_deadline: spent) }
      .to raise_error(Saboteur::BudgetPhaseTimeout)
  end

  # Fake clock: the OWN slice times out, then cleanup crosses the run
  # budget. The cause is fixed when the wait ends, so the crossing cannot
  # relabel the command's timeout as a budget stop (#305 Principal). The
  # clock JUMPS on TERM/KILL so the crossing is forced: with the old
  # post-cleanup comparison this example relabels to a budget stop.
  it "keeps an own-slice timeout generic when cleanup crosses the budget" do
    subject_in(@dir)
    runner = described_class.new(command: "sleep 30", root: @dir)
    # An advancing fake clock: a frozen one would park the reap poll.
    ticks = 0.0
    allow(runner).to receive(:monotonic) { ticks += 0.05 }
    # The clock JUMPS during the TERM/drain liveness probes, so cleanup
    # provably crosses the budget of 1.0 however fast the group dies.
    allow(runner).to receive(:tree_alive?).and_wrap_original do |method, pid|
      ticks += 1.5
      method.call(pid)
    end
    expect { runner.preflight!(deadline: 0.2, budget_deadline: 1.0) }
      .to raise_error(Saboteur::Error, /timed out/)
    expect(ticks).to be > 1.0 # the cleanup really crossed the budget
  end

  # The other side: when the run budget is the LIMITING deadline, its
  # expiry is a budget stop, not the command's error (#305 Principal).
  it "reports a budget stop when the budget is the limiting deadline" do
    subject_in(@dir)
    runner = described_class.new(command: "sleep 30", root: @dir)
    ticks = 0.0
    allow(runner).to receive(:monotonic) { ticks += 0.05 }
    expect { runner.preflight!(deadline: 2.0, budget_deadline: 0.3) }
      .to raise_error(Saboteur::BudgetPhaseTimeout)
  end

  # Fake clock: the copy eats the command's own deadline with no run
  # budget in play - a spent own deadline is the command's error, never a
  # budget stop (#305 Principal).
  it "keeps an own-deadline exhaustion at admission generic" do
    subject_in(@dir)
    runner = described_class.new(command: "true", root: @dir)
    allow(runner).to receive(:monotonic).and_return(10.0)
    expect { runner.preflight!(deadline: 0.2) }
      .to raise_error(Saboteur::Error, /deadline was spent before the command could start/)
  end

  describe "#preflight!" do
    it "passes when the command exits 0 on the unchanged copy" do
      subject_in(@dir)
      runner = described_class.new(command: "true", root: @dir)
      expect(runner.preflight!(deadline: monotonic_now + 60)).to be(true)
    end

    it "fails the run with the exit status and the command's own output" do
      subject_in(@dir)
      runner = described_class.new(command: "echo oops >&2; exit 1", root: @dir)
      expect { runner.preflight!(deadline: monotonic_now + 60) }
        .to raise_error(Saboteur::Error, /unchanged tree \(exit 1\):.*oops/m)
    end

    it "explains a 127 as the shell being unable to run the command" do
      subject_in(@dir)
      runner = described_class.new(command: "definitely-not-a-command-xyz", root: @dir)
      expect { runner.preflight!(deadline: monotonic_now + 60) }
        .to raise_error(Saboteur::Error, /exit 127 - the shell could not run the command/)
    end

    it "honors the given timeout, so the run budget caps it (#305 QA)" do
      subject_in(@dir)
      runner = described_class.new(command: "sleep 30", root: @dir)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
      expect { runner.preflight!(deadline: deadline) }.to raise_error(Saboteur::Error, /timed out/)
    end

    it "bounds the captured output" do
      subject_in(@dir)
      runner = described_class.new(command: "yes X | head -c 200000; exit 1", root: @dir)
      expect { runner.preflight!(deadline: monotonic_now + 60) }.to raise_error(Saboteur::Error) do |error|
        expect(error.message.bytesize).to be < described_class::OUTPUT_LIMIT + 200
      end
    end
  end
  # A `bundle exec saboteur` parent (or an exported BUNDLE_GEMFILE) anchors
  # the child command's bundler to the REAL tree: the mutated copy is never
  # exercised and every mutant survives (#435).
  describe "child environment (#435)" do
    def anchors
      { "BUNDLE_GEMFILE" => "/real/tree/Gemfile", "BUNDLE_BIN_PATH" => "/real/tree/bin/bundle",
        "BUNDLER_SETUP" => "/real/tree/setup.rb", "BUNDLER_VERSION" => "2.5.0",
        "BUNDLE_APP_CONFIG" => "/real/tree/.bundle" }
    end

    def with_anchors
      keys = anchors.keys
      saved = keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      saved_rubyopt = ENV.fetch("RUBYOPT", nil)
      anchors.each { |k, v| ENV[k] = v }
      ENV["RUBYOPT"] = "-W0 -rbundler/setup"
      yield
    ensure
      keys.each { |k| saved[k] ? ENV[k] = saved[k] : ENV.delete(k) }
      saved_rubyopt ? ENV["RUBYOPT"] = saved_rubyopt : ENV.delete("RUBYOPT")
    end

    it "drops bundler anchors and bundler's RUBYOPT token, keeps the rest" do
      with_anchors do
        Dir.mktmpdir do |dir|
          out = File.join(dir, "child_env.txt")
          run_in(dir, "env > #{out}")
          child = File.read(out)
          anchors.each_key { |k| expect(child).not_to include("#{k}=") }
          expect(child).to include("RUBYOPT=-W0") if child.include?("RUBYOPT")
          expect(child).not_to include("bundler/setup")
          expect(child).to include("SABOTEUR_EXTERNAL_CHILD=1")
        end
      end
    end

    it "still passes PATH and HOME through" do
      with_anchors do
        Dir.mktmpdir do |dir|
          out = File.join(dir, "child_env.txt")
          run_in(dir, "env > #{out}")
          child = File.read(out)
          expect(child).to include("PATH=")
          expect(child).to include("HOME=")
        end
      end
    end
  end
end
