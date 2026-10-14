# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Runner, :fixture do
  def passing_responder(&extra)
    lambda do |argv|
      extra&.call(argv)
      if argv.include?("rubocop")
        next PreflightSupport::ScriptedRunner.new.result(argv, 0,
                                                         PreflightSupport.fixture_text("rubocop_clean.json"))
      end

      if argv.include?("rspec")
        next PreflightSupport::ScriptedRunner.new.result(argv, 0, "",
                                                         data: PreflightSupport.fixture_text("rspec_clean.json"))
      end
      next PreflightSupport::ScriptedRunner.new.result(argv, 0, "Bundler version 2.5.3\n") if argv.include?("--version")

      nil
    end
  end

  def run_in_fixture(mode:, responder: passing_responder)
    scripted = PreflightSupport::ScriptedRunner.new(&responder)
    # Git commands go to a real runner; everything else is scripted.
    real = @fixture.runner
    router = Object.new
    router.define_singleton_method(:run) do |argv, **options|
      argv.first == "git" ? real.run(argv, **options) : scripted.run(argv, **options)
    end
    options = @fixture.options(base: @base, mode: mode)
    described_class.new(options: options, directory: @fixture.directory, command_runner: router,
                        run_id: "test-run", env: { "PATH" => ENV.fetch("PATH") }).call
  end

  before do
    # Ordinary runs start with an ignored lockfile already present, like a normal checkout.
    File.open(File.join(@fixture.directory, ".git/info/exclude"), "a") { |file| file.puts("Gemfile.lock") }
    File.write(File.join(@fixture.directory, "Gemfile.lock"), "present\n")
  end

  def good_change
    @fixture.write("lib/ok.rb", "# SPDX-License-Identifier: MIT\n")
    @fixture.commit("good")
  end

  it "full mode with everything passing is still partial, because dogfood is not implemented" do
    good_change
    report = run_in_fixture(mode: "full")
    statuses = report.to_h[:checks].to_h { |check| [check[:name], check[:status]] }
    expect(report.verdict).to eq("partial")
    expect(statuses).to include("rubocop" => :passed, "full_suite" => :passed, "changed_method_dogfood" => :not_run)
  end

  it "fast mode is partial and does not run the full suite" do
    good_change
    report = run_in_fixture(mode: "fast")
    names = report.to_h[:checks].map { |check| check[:name] }
    expect([report.verdict, names]).to match(["partial", array_excluding("full_suite")])
  end

  it "skips the costly checks when a cheap check failed and says why" do
    @fixture.write("lib/ok.rb", "# SPDX-License-Identifier: MIT\n")
    @fixture.commit("unsigned", signoff: nil)
    report = run_in_fixture(mode: "full")
    skipped = report.to_h[:checks].select { |check| check[:name] == "rubocop" }.first
    expect([report.verdict, skipped[:status], skipped[:reason]]).to match(["failed", :not_run, /earlier check/])
  end

  it "fails an empty change set instead of passing it" do
    @fixture.git("commit", "-q", "--allow-empty", "-m", "empty\n\nSigned-off-by: Fixture Author <author@example.test>")
    report = run_in_fixture(mode: "full")
    expect([report.verdict, report.to_h[:checks].first[:name]]).to eq(%w[failed change_inventory])
  end

  it "is incomplete when the tree changes while the checks run" do
    good_change
    mutate = ->(argv) { @fixture.write("late.txt", "x\n") if argv.include?("rubocop") }
    report = run_in_fixture(mode: "full", responder: passing_responder(&mutate))
    expect(report.verdict).to eq("incomplete")
  end

  it "writes a report and records a swallowed-status RuboCop failure as incomplete, not passed" do
    good_change
    lying = lambda do |argv|
      clean = PreflightSupport.fixture_text("rubocop_clean.json")
      PreflightSupport::ScriptedRunner.new.result(argv, 1, clean) if argv.include?("rubocop")
    end
    report = run_in_fixture(mode: "full", responder: lying)
    expect(report.verdict).to eq("incomplete")
    expect(File.exist?(File.join(@fixture.directory, "tmp/preflight/test-run/report.json"))).to be(true)
  end

  it "still runs the costly checks when only a check-policy notice was raised" do
    @fixture.write(".rubocop.yml", "AllCops:\n  NewCops: enable\n")
    @fixture.commit("policy edit")
    report = run_in_fixture(mode: "fast")
    statuses = report.to_h[:checks].to_h { |check| [check[:name], check[:status]] }
    expect(statuses).to include("check_policy_changes" => :review_required, "rubocop" => :passed)
  end

  it "stops at the first failing costly check and never runs the later stages" do
    good_change
    calls = []
    failing = lambda do |argv|
      calls << argv
      next PreflightSupport::ScriptedRunner.new.result(argv, 0, "Bundler version 2.5.3\n") if argv.include?("--version")
      next unless argv.include?("rubocop")

      PreflightSupport::ScriptedRunner.new.result(argv, 1, PreflightSupport.fixture_text("rubocop_offense.json"))
    end
    report = run_in_fixture(mode: "full", responder: failing)
    statuses = report.to_h[:checks].to_h { |check| [check[:name], check[:status]] }
    expect(statuses).to include("rubocop" => :failed, "harness_specs" => :not_run, "full_suite" => :not_run)
    expect(calls.flatten).not_to include("rspec")
  end

  it "records provenance: rerun command, policy digest, per-file blobs and modes, command log" do
    good_change
    data = run_in_fixture(mode: "fast").to_h
    expect(data[:provenance]).to include(rerun_command: a_string_including("--mode fast"),
                                         trusted_policy_sha256: a_string_matching(/\A\h{64}\z/))
    expect(data[:changed_files].first).to include(path: "lib/ok.rb", new_mode: "100644")
    expect(data[:changed_files].first[:new_blob]).to match(/\A\h{40}\z/)
  end

  it "never invokes bundle or a candidate Gemfile when a protected file changed (negative control below)" do
    @fixture.write(".github/workflows/evil.yml", "x\n")
    @fixture.commit("workflow")
    calls = []
    report = run_in_fixture(mode: "full", responder: passing_responder { |argv| calls << argv })
    expect([report.verdict, calls.flatten.grep(/bundle|rspec|rubocop/)]).to eq(["failed", []])
  end

  it "does probe dependencies when nothing blocks it (valid control)" do
    good_change
    calls = []
    run_in_fixture(mode: "fast", responder: passing_responder { |argv| calls << argv })
    expect(calls).to include(%w[bundle list])
  end

  %w[tmp tmp/preflight].each do |link|
    it "writes nothing outside the checkout when #{link} is a symlink" do
      good_change
      outside = Dir.mktmpdir("outside")
      FileUtils.mkdir_p(File.join(@fixture.directory, "tmp")) if link == "tmp/preflight"
      File.symlink(outside, File.join(@fixture.directory, link))
      options = @fixture.options(base: @base, mode: "fast")
      expect { described_class.new(options: options, directory: @fixture.directory).call }
        .to raise_error(Preflight::UnverifiableInput, /symlink/)
      expect(Dir.children(outside)).to be_empty
    ensure
      FileUtils.remove_entry(outside)
    end
  end

  it "reports a rerun command in the `ruby script/preflight` form" do
    good_change
    expect(run_in_fixture(mode: "fast").to_h[:provenance][:rerun_command]).to start_with("ruby script/preflight --base")
  end

  describe "dependency preparation in a fresh checkout" do
    def lock_path
      File.join(@fixture.directory, "Gemfile.lock")
    end

    before do
      FileUtils.rm_f(lock_path)
    end

    it "accepts the lockfile that preparation (bundle lock --local) creates, with no rerun needed (valid control)" do
      good_change
      report = run_in_fixture(mode: "fast", responder: passing_responder do |argv|
        File.write(lock_path, "locked\n") if argv == %w[bundle lock --local]
      end)
      expect([report.verdict, report.to_h[:invalidated_by]]).to eq(["partial", nil])
    end

    it "does not run lock preparation when a lockfile already exists" do
      good_change
      File.write(lock_path, "present\n")
      calls = []
      run_in_fixture(mode: "fast", responder: passing_responder { |argv| calls << argv })
      expect(calls).not_to include(%w[bundle lock --local])
    end

    it "is incomplete, and does not recreate the lockfile, when it is deleted during the checks" do
      good_change
      File.write(lock_path, "present\n")
      report = run_in_fixture(mode: "fast", responder: passing_responder do |argv|
        FileUtils.rm_f(lock_path) if argv.include?("rubocop")
      end)
      expect([report.verdict, File.exist?(lock_path)]).to eq(["incomplete", false])
    end

    it "is incomplete when preparation reports success but leaves no lockfile" do
      good_change
      report = run_in_fixture(mode: "fast")
      expect(report.to_h[:checks].map { |c| [c[:name], c[:status]] }).to include(["execution_inputs", :incomplete])
    end

    it "still catches a lockfile that changes after preparation" do
      good_change
      report = run_in_fixture(mode: "fast", responder: passing_responder do |argv|
        File.write(lock_path, "late #{Time.now.to_f}\n") if argv.include?("rspec") || argv.include?("rubocop")
        File.write(lock_path, "locked\n") if argv == %w[bundle lock --local]
      end)
      expect(report.verdict).to eq("incomplete")
    end

    it "makes the run incomplete when preparation changes a tracked file" do
      good_change
      File.write(lock_path, "present\n")
      report = run_in_fixture(mode: "fast", responder: passing_responder do |argv|
        File.write(File.join(@fixture.directory, "lib/ok.rb"), "tampered\n") if argv == %w[bundle list]
      end)
      expect([report.verdict, report.to_h[:checks].map { |c| c[:name] }]).to include("incomplete")
    end
  end

  describe "an injected environment" do
    it "is used for probing, fingerprinting and execution, with no ambient variables leaking in" do
      good_change
      stubs = Dir.mktmpdir("stubs")
      alt = File.join(stubs, "AltGemfile")
      log = File.join(stubs, "calls.log")
      File.write(alt, "")
      File.write(File.join(stubs, "ruby"), "#!/bin/sh\nexit 0\n", perm: 0o755)
      File.write(File.join(stubs, "bundle"), <<~SH, perm: 0o755)
        #!/bin/sh
        echo "$1 gemfile=$BUNDLE_GEMFILE mark=$PREFLIGHT_MARK ambient=${HOME:-none}" >> "$STUB_LOG"
        [ "$1" = "lock" ] && touch "$BUNDLE_GEMFILE.lock"
        [ "$1" = "exec" ] && exit 1
        echo "Bundler version stub"
      SH
      env = { "PATH" => "#{stubs}:/usr/bin:/bin", "BUNDLE_GEMFILE" => alt, "PREFLIGHT_MARK" => "alt",
              "STUB_LOG" => log }
      options = @fixture.options(base: @base, mode: "fast")
      report = described_class.new(options: options, directory: @fixture.directory, env: env, run_id: "env-run").call
      lines = File.readlines(log)
      expect(lines.map { |l| l.split.first }).to include("lock", "--version", "list", "exec")
      expect(lines).to all(include("gemfile=#{alt}", "mark=alt", "ambient=none"))
      expect(report.verdict).to eq("incomplete")
    ensure
      FileUtils.remove_entry(stubs)
    end
  end
end

RSpec.describe Preflight::Runner, "candidate-time output swaps", :fixture do
  let(:run_id) { "swap-run" }
  let(:stubs) { Dir.mktmpdir("stubs") }
  let(:outside) { Dir.mktmpdir("outside") }

  after do
    FileUtils.remove_entry(stubs)
    FileUtils.remove_entry(outside)
  end

  def run_directory
    File.join(File.realpath(@fixture.directory), "tmp/preflight", run_id)
  end

  # A stand-in for bundle. Its `exec rubocop` and `exec rspec` branches behave like candidate code that tampers with
  # the harness's output directory while the checks run. Everything else succeeds.
  def install_stubs(tamper)
    File.write(File.join(stubs, "ruby"), "#!/bin/sh\nexit 0\n", perm: 0o755)
    File.write(File.join(stubs, "bundle"), <<~SH, perm: 0o755)
      #!/bin/sh
      if [ "$1" = "lock" ]; then touch "$BUNDLE_GEMFILE.lock"; exit 0; fi
      if [ "$1" = "exec" ] && [ "$2" = "rubocop" ]; then
        #{tamper == :logs_symlink ? 'mv "$RUN/logs" "$RUN/logs.old" && ln -s "$OUTSIDE" "$RUN/logs"' : ':'}
        #{tamper == :report_fifo ? 'mkfifo "$RUN/report.json"' : ':'}
        cat "$RUBOCOP_JSON"; exit 0
      fi
      if [ "$1" = "exec" ] && [ "$2" = "rspec" ]; then
        #{tamper == :raw_symlink ? 'ln -s "$OUTSIDE_FILE" "$RUN/logs/harness_specs.rspec.json"' : ':'}
        cat "$RSPEC_JSON"
        exit 0
      fi
      echo "Bundler version stub"
    SH
  end

  def write_stub_documents
    File.write(File.join(stubs, "Gemfile"), "")
    File.write(File.join(stubs, "outside_rspec.json"), PreflightSupport.fixture_text("rspec_clean.json"))
    File.write(File.join(stubs, "rubocop.json"), PreflightSupport.fixture_text("rubocop_clean.json"))
  end

  def run_swap(tamper, victim: nil)
    good = "# SPDX-License-Identifier: MIT\n"
    @fixture.write("lib/ok.rb", good)
    @fixture.commit("good")
    install_stubs(tamper)
    write_stub_documents
    env = { "PATH" => "#{stubs}:/usr/bin:/bin", "BUNDLE_GEMFILE" => File.join(stubs, "Gemfile"),
            "RUN" => run_directory, "OUTSIDE" => outside, "RUBOCOP_JSON" => File.join(stubs, "rubocop.json"),
            "RSPEC_JSON" => File.join(stubs, "outside_rspec.json"), "OUTSIDE_FILE" => victim.to_s }
    options = @fixture.options(base: @base, mode: "fast")
    Timeout.timeout(30) do
      described_class.new(options: options, directory: @fixture.directory, env: env, run_id: run_id).call
    end
  end

  it "refuses an injected run id that is not one safe path component" do
    options = @fixture.options(base: @base, mode: "fast")
    ["../x", "a/b", "..", ".", "", "-x", "a b"].each do |bad|
      expect { described_class.new(options: options, directory: @fixture.directory, env: {}, run_id: bad) }
        .to raise_error(ArgumentError, /run_id/)
    end
  end

  it "passes when nothing tampers (valid control)" do
    expect(run_swap(:none).verdict).to eq("partial")
  end

  it "does not write logs through a logs directory that was swapped for a symlink" do
    report = run_swap(:logs_symlink)
    expect([report.verdict, Dir.children(outside)]).to eq(["incomplete", []])
  end

  it "does not hang or pass when the report path was replaced by a FIFO" do
    expect(run_swap(:report_fifo).verdict).to eq("incomplete")
  end

  it "writes the raw RSpec report to a harness-owned pipe, so a planted link in the old path is never written" do
    victim = File.join(outside, "victim.txt")
    File.write(victim, "untouched\n")
    report = run_swap(:raw_symlink, victim: victim)
    expect([File.read(victim), report.verdict]).to eq(%W[untouched\n incomplete])
  end

  it "reads the raw RSpec report through the pipe in a real run (valid control)" do
    report = run_swap(:none)
    expect(report.to_h[:checks].find { |c| c[:name] == "harness_specs" }[:status]).to eq(:passed)
  end
end
