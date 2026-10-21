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
  it "accepts a subject file spelled through a symlinked root" do
    # macOS tmp dirs are /var/folders/... symlinked to /private/var/...: the
    # runner canonicalizes its root while the subject keeps the spelled path,
    # and the containment check must still recognize the file as inside (#442).
    real = Dir.mktmpdir
    Dir.mktmpdir do |holder|
      link = File.join(holder, "link")
      File.symlink(real, link)
      outcome, = run_in(link, "true")
      expect(outcome.status).to eq(:survived)
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

    # Proof through a real spawned child, read back through the runner's
    # own bounded capture instead of a `env > file` bridge: on the macOS
    # runners the bridged file never appeared (ENOENT at File.read), and
    # the bridge could only fail silently - a spawn error is reported as
    # an Outcome, not raised. The capture shows the child's bytes (or sh's
    # own error) either way, so a failure names its cause.
    def child_env_output(dir)
      outcome, runner, = run_in(dir, "env")
      expect(outcome.status).to eq(:survived), "the env child never ran: #{outcome.message}"
      runner.send(:last_output)
    end

    it "drops bundler anchors and bundler's RUBYOPT token, keeps the rest" do
      with_anchors do
        # unbundled_env starts from the pre-bundler environment, not the
        # current ENV: the anchors and a bundler-token RUBYOPT must be in
        # ORIGINAL_ENV for the scrub to be exercised at all.
        stub_const("Bundler::ORIGINAL_ENV",
                   Bundler::ORIGINAL_ENV.merge(anchors).merge("RUBYOPT" => "-W0 -rbundler/setup"))
        Dir.mktmpdir do |dir|
          child = child_env_output(dir)
          anchors.each_key { |k| expect(child).not_to include("#{k}=") }
          expect(child).to include("RUBYOPT=-W0")
          expect(child).not_to include("bundler/setup")
          expect(child).to include("SABOTEUR_EXTERNAL_CHILD=1")
        end
      end
    end

    it "still passes PATH and HOME through" do
      with_anchors do
        Dir.mktmpdir do |dir|
          child = child_env_output(dir)
          expect(child).to include("PATH=")
          expect(child).to include("HOME=")
        end
      end
    end

    # with_unbundled_env strips every BUNDLE_* key (bundler's
    # unbundled_env deletes the whole prefix), including settings the
    # SHELL exported - CI commonly exports BUNDLE_PATH without writing
    # .bundle/config, and dropping it leaves the child's bundler unable
    # to find the app's gems (#449).
    describe "env-exported bundler settings (#449)" do
      # A shell export is present in the pre-bundler environment
      # (ORIGINAL_ENV); a value bundler itself activated is not.
      def with_bundle_path(original:)
        saved = ENV.fetch("BUNDLE_PATH", nil)
        ENV["BUNDLE_PATH"] = "/ci/gems"
        base = Bundler::ORIGINAL_ENV
        # The ambient shell may itself export BUNDLE_PATH (a CI sandbox with a
        # gem path configured); a base.dup would carry it into the stubbed
        # ORIGINAL_ENV and the child-env passthrough would re-add it, failing
        # the original:false specs on machines whose shells export it.
        stub_const("Bundler::ORIGINAL_ENV", # unfrozen, like the real one
                   original ? base.merge("BUNDLE_PATH" => "/ci/gems") : base.except("BUNDLE_PATH"))
        yield
      ensure
        saved ? ENV["BUNDLE_PATH"] = saved : ENV.delete("BUNDLE_PATH")
      end

      it "re-adds a BUNDLE_PATH the shell exported" do
        with_bundle_path(original: true) do
          Dir.mktmpdir do |dir|
            expect(child_env_output(dir)).to include("BUNDLE_PATH=/ci/gems")
          end
        end
      end

      it "still drops a BUNDLE_PATH that bundler itself activated" do
        with_bundle_path(original: false) do
          Dir.mktmpdir do |dir|
            expect(child_env_output(dir)).not_to include("BUNDLE_PATH=")
          end
        end
      end

      it "builds the child env without Bundler loaded at all" do
        hide_const("Bundler")
        runner = described_class.new(command: "true", root: @dir)
        env = runner.send(:child_env)
        expect(env["SABOTEUR_EXTERNAL_CHILD"]).to eq("1")
        expect(env).not_to have_key("BUNDLE_GEMFILE")
      end

      it "does not re-add a passthrough key missing from the pre-bundler environment, not even nil-valued" do
        with_bundle_path(original: false) do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)).not_to have_key("BUNDLE_PATH")
        end
      end
    end

    # A relocated/toolcache Ruby needs its own rubylibdir in RUBYLIB to
    # find stdlib; bundler's unbundled scrub drops the entry when it
    # coincides with what bundler itself adds, and the child dies at
    # "cannot load such file -- rubygems" (#584).
    describe "RUBYLIB stdlib entries (#584)" do
      let(:rubylibdir) { RbConfig::CONFIG["rubylibdir"] }
      let(:exported) { [rubylibdir, "/app/lib"].join(File::PATH_SEPARATOR) }

      def with_rubylib_scrub(original_rubylib:, scrubbed_rubylib:)
        saved = ENV.fetch("RUBYLIB", nil)
        ENV["RUBYLIB"] = exported
        original_env = Bundler::ORIGINAL_ENV.dup
        original_rubylib ? original_env["RUBYLIB"] = original_rubylib : original_env.delete("RUBYLIB")
        stub_const("Bundler::ORIGINAL_ENV", original_env)
        allow(Bundler).to receive(:with_unbundled_env) do |&block|
          inner = ENV.fetch("RUBYLIB", nil)
          scrubbed_rubylib.nil? ? ENV.delete("RUBYLIB") : ENV["RUBYLIB"] = scrubbed_rubylib
          block.call
        ensure
          inner.nil? ? ENV.delete("RUBYLIB") : ENV["RUBYLIB"] = inner
        end
        yield
      ensure
        saved.nil? ? ENV.delete("RUBYLIB") : ENV["RUBYLIB"] = saved
      end

      it "restores a shell-exported rubylibdir entry bundler's scrub dropped" do
        with_rubylib_scrub(original_rubylib: exported, scrubbed_rubylib: "/app/lib") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"].split(File::PATH_SEPARATOR)).to include(rubylibdir)
        end
      end

      it "does not re-add a RUBYLIB entry that was never in the pre-bundler environment" do
        with_rubylib_scrub(original_rubylib: nil, scrubbed_rubylib: "/bundler/lib") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"].to_s.split(File::PATH_SEPARATOR)).to eq(["/bundler/lib"])
        end
      end

      # RUBYLIB is ordered: two directories providing the same feature load
      # in path order, so the restored entries keep their pre-bundler
      # order - /first before /second, not appended behind the survivors.
      it "keeps the pre-bundler order of restored entries (duplicate-feature precedence)" do
        with_rubylib_scrub(original_rubylib: "/first:/second", scrubbed_rubylib: "/second") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"]).to eq("/first:/second")
        end
      end

      it "preserves scrubbed RUBYLIB bytes when there was no original export" do
        with_rubylib_scrub(original_rubylib: nil, scrubbed_rubylib: "/one:/two:") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"]).to eq("/one:/two:")
        end
      end

      it "restores exported paths when the scrub removed RUBYLIB entirely" do
        with_rubylib_scrub(original_rubylib: "/first", scrubbed_rubylib: nil) do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"]).to eq("/first")
        end
      end

      it "appends each distinct scrubbed path after restored paths" do
        with_rubylib_scrub(original_rubylib: "/first:/second", scrubbed_rubylib: "/second:/third") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"]).to eq("/first:/second:/third")
        end
      end

      it "does not resurrect an entry bundler itself added and the scrub removed" do
        with_rubylib_scrub(original_rubylib: "/app/lib", scrubbed_rubylib: "/app/lib") do
          runner = described_class.new(command: "true", root: @dir)
          expect(runner.send(:child_env)["RUBYLIB"]).to eq("/app/lib")
        end
      end
    end
  end

  describe "Gemfile path: sources (#644)" do
    def source_row(name:, original:, expanded:)
      Saboteur::Execution::GemfilePathSources::Source.new(name: name, original: original, expanded: expanded)
    end

    it "refuses a relative path: source that resolves outside the root, naming it" do
      Dir.mktmpdir do |dir|
        row = source_row(name: "mygem", original: "../mygem", expanded: "/elsewhere/mygem")
        expect { described_class.new(command: "true", root: dir, path_sources: [row]) }
          .to raise_error(Saboteur::ConfigError,
                          'the Gemfile\'s path: source "mygem" (../mygem) resolves outside the project root ' \
                          "(/elsewhere/mygem); external test commands need a self-contained tree")
      end
    end

    it "rebases an absolute path: source pointing into the original tree into the copy" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{dir}/engines/mygem\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "PATH\n  remote: #{dir}/engines/mygem\n  specs:\n\nGEM\n")
        original = File.join(dir, "engines", "mygem")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          gemfile = File.read(File.join(copy, "Gemfile"))
          lockfile = File.read(File.join(copy, "Gemfile.lock"))
          expect(gemfile).to eq("gem \"mygem\", path: \"#{copy}/engines/mygem\"\n")
          expect(lockfile).to include("remote: #{copy}/engines/mygem")
        end
      end
    end

    it "tolerates a missing Gemfile.lock: the Gemfile rewrite proceeds without one (#729)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{dir}/engines/mygem\"\n")
        original = File.join(dir, "engines", "mygem")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          gemfile = File.read(File.join(copy, "Gemfile"))
          expect(gemfile).to eq("gem \"mygem\", path: \"#{copy}/engines/mygem\"\n")
          expect(File.exist?(File.join(copy, "Gemfile.lock"))).to be(false)
        end
      end
    end

    it "rebases an absolute path: source equal to the project root onto the copy root (#722)" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{dir}\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "PATH\n  remote: #{dir}\n  specs:\n\nGEM\n")
        row = source_row(name: "mygem", original: dir, expanded: dir)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          gemfile = File.read(File.join(copy, "Gemfile"))
          lockfile = File.read(File.join(copy, "Gemfile.lock"))
          expect(gemfile).to eq("gem \"mygem\", path: \"#{copy}\"\n")
          expect(lockfile).to include("remote: #{copy}")
        end
      end
    end

    it 'accepts the lockfile relative "." spelling for a root path: source (#729)' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{dir}\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "PATH\n  remote: .\n  specs:\n\nGEM\n")
        row = source_row(name: "mygem", original: dir, expanded: dir)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          lockfile = File.read(File.join(copy, "Gemfile.lock"))
          expect(lockfile).to include("remote: .")
        end
      end
    end

    it "escapes the path spellings before matching the lockfile remote (#729)" do
      Dir.mktmpdir("proj.x") do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        original = File.join(dir, "engines", "mygem")
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{original}\"\n")
        decoy = original.sub("proj.x", "proj3x")
        File.write(File.join(dir, "Gemfile.lock"),
                   "PATH\n  remote: #{original}\n  specs:\n\nPATH\n  remote: #{decoy}\n  specs:\n\nGEM\n")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          lockfile = File.read(File.join(copy, "Gemfile.lock"))
          expect(lockfile).to include("remote: #{copy}/engines/mygem")
        end
      end
    end

    it "leaves a read-only lockfile untouched when the remote already fits the copy (#729)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "vend", "g"))
        original = File.join(dir, "vend", "g")
        File.write(File.join(dir, "Gemfile"), "gem \"g\", path: \"#{original}\"\n")
        lock = File.join(dir, "Gemfile.lock")
        File.write(lock, "PATH\n  remote: vend/g\n  specs:\n\nGEM\n")
        row = source_row(name: "g", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        # cp_r preserves the 0444 mode into the copy, so any rewrite attempt
        # raises EACCES for a mortal user; the write spy keeps the pin live
        # where root ignores the permission bits (#305).
        FileUtils.chmod(0o444, lock)
        begin
          writes = []
          allow(File).to receive(:write).and_wrap_original do |original, target, *args|
            writes << target
            original.call(target, *args)
          end
          expect { runner.send(:with_fresh_copy) { nil } }.not_to raise_error
          expect(writes.grep(/Gemfile\.lock\z/)).to be_empty
        ensure
          FileUtils.chmod(0o644, lock)
        end
      end
    end

    it "rewrites the real remote and not an earlier decoy section (#729)" do
      Dir.mktmpdir("proj.x") do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        original = File.join(dir, "engines", "mygem")
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{original}\"\n")
        decoy = original.sub("proj.x", "proj3x")
        File.write(File.join(dir, "Gemfile.lock"),
                   "PATH\n  remote: #{decoy}\n  specs:\n\nPATH\n  remote: #{original}\n  specs:\n\nGEM\n")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          lockfile = File.read(File.join(copy, "Gemfile.lock"))
          expect(lockfile).to include("remote: #{copy}/engines/mygem")
          expect(lockfile).to include("remote: #{decoy}")
        end
      end
    end

    it "states the lockfile refusal with the source name, original path, and remedy (#729)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        original = File.join(dir, "engines", "mygem")
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{original}\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "GEM\n  specs:\n")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        expect { runner.send(:with_fresh_copy) { nil } }
          .to raise_error(Saboteur::ConfigError,
                          "could not rebase the lockfile's PATH remote for path: source \"mygem\" " \
                          "(#{original}); the lockfile must record it exactly once - run bundle install")
      end
    end

    it "refuses when the lockfile does not record the source exactly once (#722)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        original = File.join(dir, "engines", "mygem")
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{original}\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "GEM\n  specs:\n")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        expect { runner.send(:with_fresh_copy) { nil } }
          .to raise_error(Saboteur::ConfigError,
                          /could not rebase the lockfile's PATH remote for path: source "mygem"/)
      end
    end

    it "refuses when the lockfile records the source twice (#722)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        original = File.join(dir, "engines", "mygem")
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: \"#{original}\"\n")
        lockfile = "PATH\n  remote: #{original}\n  specs:\n\nPATH\n  remote: #{original}\n  specs:\n\nGEM\n"
        File.write(File.join(dir, "Gemfile.lock"), lockfile)
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        expect { runner.send(:with_fresh_copy) { nil } }
          .to raise_error(Saboteur::ConfigError,
                          /could not rebase the lockfile's PATH remote for path: source "mygem"/)
      end
    end

    it "accepts a lockfile spelling an in-project source relatively, as bundle lock writes it (#722)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "vend", "g"))
        File.write(File.join(dir, "vend", "g", "g.gemspec"),
                   "Gem::Specification.new { |s| s.name = \"g\"; s.version = \"0.1.0\"; " \
                   "s.authors = [\"x\"]; s.summary = \"x\" }\n")
        original = File.join(dir, "vend", "g")
        File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"g\", path: \"#{original}\"\n")
        # The exact layout a real `bundle lock --local` writes for this
        # Gemfile (captured against bundler 2.5.22 and 4.0.23): an
        # in-project path: source lands as a ROOT-RELATIVE remote. The
        # lockfile is written by hand, not produced here: under
        # `bundle exec` the child inherits RUBYOPT=-rbundler/setup and
        # BUNDLER_SETUP, and bundler 4 then locks the OUTER project's
        # Gemfile.lock instead of the tmpdir's (#732 CI).
        File.write(File.join(dir, "Gemfile.lock"), <<~LOCK)
          PATH
            remote: vend/g
            specs:
              g (0.1.0)

          GEM
            remote: https://rubygems.org/
            specs:

          PLATFORMS
            ruby
            x86_64-linux

          DEPENDENCIES
            g!

          BUNDLED WITH
             2.5.22
        LOCK

        row = source_row(name: "g", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])
        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          expect(File.read(File.join(copy, "Gemfile"))).to include("path: \"#{copy}/vend/g\"")
          expect(File.read(File.join(copy, "Gemfile.lock"))).to include("remote: vend/g")
        end
      end
    end

    it "accepts a lockfile relative spelling behind a symlinked root (#722)" do
      Dir.mktmpdir do |dir|
        real = File.join(dir, "real")
        FileUtils.mkdir_p(File.join(real, "vend", "g"))
        File.write(File.join(real, "vend", "g", "g.gemspec"),
                   "Gem::Specification.new { |s| s.name = \"g\"; s.version = \"0.1.0\"; " \
                   "s.authors = [\"x\"]; s.summary = \"x\" }\n")
        link = File.join(dir, "link")
        File.symlink(real, link)
        # The Gemfile spells the source THROUGH the symlink and Bundler's
        # expanded_original_path is a textual expand_path, so neither is
        # realpath'd - while the runner realpaths the root (macOS /var ->
        # /private/var, #732 CI).
        original = File.join(link, "vend", "g")
        File.write(File.join(real, "Gemfile"), "source \"https://rubygems.org\"\ngem \"g\", path: \"#{original}\"\n")
        File.write(File.join(real, "Gemfile.lock"), <<~LOCK)
          PATH
            remote: vend/g
            specs:
              g (0.1.0)

          GEM
            remote: https://rubygems.org/
            specs:

          PLATFORMS
            ruby
            x86_64-linux

          DEPENDENCIES
            g!

          BUNDLED WITH
             2.5.22
        LOCK

        row = source_row(name: "g", original: original, expanded: File.expand_path(original))
        runner = described_class.new(command: "true", root: link, path_sources: [row])
        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          expect(File.read(File.join(copy, "Gemfile"))).to include("path: \"#{copy}/vend/g\"")
          expect(File.read(File.join(copy, "Gemfile.lock"))).to include("remote: vend/g")
        end
      end
    end

    it "refuses a source whose literal path: option is not in the Gemfile exactly once" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem \"mygem\", path: computed_path\n")
        original = File.join(dir, "engines", "mygem")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: dir, path_sources: [row])

        expect { runner.send(:with_fresh_copy) { nil } }
          .to raise_error(Saboteur::ConfigError, /could not rebase the Gemfile's path: source "mygem"/)
      end
    end

    it "leaves relative inside-root and absolute outside-root sources untouched" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "engines", "rel"))
        gemfile_text = "gem \"rel\", path: \"engines/rel\"\ngem \"ext\", path: \"/opt/ext\"\n"
        File.write(File.join(dir, "Gemfile"), gemfile_text)
        rows = [
          source_row(name: "rel", original: "engines/rel", expanded: File.join(dir, "engines", "rel")),
          source_row(name: "ext", original: "/opt/ext", expanded: "/opt/ext")
        ]
        runner = described_class.new(command: "true", root: dir, path_sources: rows)

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          expect(File.read(File.join(copy, "Gemfile"))).to eq(gemfile_text)
        end
      end
    end

    it "accepts a gemspec's root path source in a gem-style project (#644)" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "tool.gemspec"),
                   "Gem::Specification.new { |s| s.name = \"tool\"; s.version = \"0.1.0\"; s.authors = [\"x\"]; " \
                   "s.summary = \"x\" }\n")
        FileUtils.mkdir_p(File.join(dir, "vend", "inner"))
        File.write(File.join(dir, "Gemfile"),
                   "source \"https://rubygems.org\"\ngemspec\ngem \"inner\", path: \"vend/inner\"\n")

        expect { described_class.new(command: "true", root: dir) }.not_to raise_error
      end
    end

    it "rebases absolute path: sources from the command's pinned BUNDLE_GEMFILE into its copy" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "gemfiles"))
        FileUtils.mkdir_p(File.join(dir, "engines", "mygem"))
        File.write(File.join(dir, "gemfiles", "custom.gemfile"),
                   "gem \"mygem\", path: \"#{dir}/engines/mygem\"\n")
        File.write(File.join(dir, "gemfiles", "custom.gemfile.lock"),
                   "PATH\n  remote: #{dir}/engines/mygem\n  specs:\n\nGEM\n")
        File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\n")
        runner = described_class.new(command: "BUNDLE_GEMFILE=gemfiles/custom.gemfile bundle exec rspec", root: dir)

        runner.send(:with_fresh_copy) do
          copy = runner.instance_variable_get(:@copy_root)
          expect(File.read(File.join(copy, "gemfiles", "custom.gemfile")))
            .to eq("gem \"mygem\", path: \"#{copy}/engines/mygem\"\n")
          expect(File.read(File.join(copy, "gemfiles", "custom.gemfile.lock")))
            .to include("remote: #{copy}/engines/mygem")
          expect(File.read(File.join(copy, "Gemfile"))).to eq("source \"https://rubygems.org\"\n")
        end
      end
    end

    it "refuses a BUNDLE_GEMFILE pinned outside the project root" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |other|
          File.write(File.join(other, "elsewhere.gemfile"), "gem \"x\", path: \"rel\"\n")
          expect do
            described_class.new(command: "BUNDLE_GEMFILE=#{other}/elsewhere.gemfile bundle exec rspec", root: dir)
          end.to raise_error(Saboteur::ConfigError, /pins BUNDLE_GEMFILE .* outside the project root/)
        end
      end
    end

    it "classifies canonically when the root sits behind a symlink and the source path does not exist yet (#644)" do
      Dir.mktmpdir do |dir|
        real = File.join(dir, "real")
        FileUtils.mkdir_p(real)
        link = File.join(dir, "link")
        File.symlink(real, link)
        File.write(File.join(real, "Gemfile"), "gem \"mygem\", path: computed_path\n")
        original = File.join(link, "engines", "mygem")
        row = source_row(name: "mygem", original: original, expanded: original)
        runner = described_class.new(command: "true", root: link, path_sources: [row])

        expect { runner.send(:with_fresh_copy) { nil } }
          .to raise_error(Saboteur::ConfigError, /could not rebase the Gemfile's path: source "mygem"/)
      end
    end
  end
end
