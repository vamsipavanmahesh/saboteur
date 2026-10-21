# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "doctor", :e2e do
  def doctor(dir, *arguments)
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE,
                                      "doctor", *arguments, chdir: dir)
    # The subprocess writes UTF-8; the pipe inherits the spec run's locale.
    [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
  end

  it "prints the check summary by default, without running the suite or writing anything" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "failure_spec.rb"),
               'RSpec.describe("red") { it("fails") { expect(true).to eq(false) } }')
    out, err, status = doctor(dir)
    expect(status.exitstatus).to eq(0), err
    expect(out).to include("Doctor summary (details: saboteur doctor -v):")
    expect(out).to match(/Ruby \d+\.\d+\.\d+ . RSpec \d+\.\d+/)
    expect(out).not_to include("Ruby:", "Baseline:", "passed twice")
    expect(File).not_to exist(File.join(dir, ".saboteur"))
  end

  it "keeps the full environment detail under -v, without running the suite or writing anything" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "failure_spec.rb"),
               'RSpec.describe("red") { it("fails") { expect(true).to eq(false) } }')
    out, err, status = doctor(dir, "--verbose")
    expect(status.exitstatus).to eq(0), err
    expect(out).to include("Ruby:", "Coverage: suspended", "Integration: rspec", "Baseline: not run", "--suite")
    expect(out).not_to include("passed twice")
    expect(out.scan(/^Coverage:/).size).to eq(1)
    expect(out.scan(/^Sandbox:/).size).to eq(1)
    expect(File).not_to exist(File.join(dir, ".saboteur"))
  end

  it "checks two seeded baselines with --suite without writing caches or reports" do
    dir = copy_fixture("people")
    out, err, status = doctor(dir, "--suite", "--seed", "42", "--verbose")
    expect(status.exitstatus).to eq(0), err
    expect(out).to include("Ruby:", "Coverage: suspended", "Integration: rspec", "passed twice", "seed 42")
    expect(File).not_to exist(File.join(dir, ".saboteur"))
  end

  it "warns about wrong-form ignore subjects without changing the ignore file" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "lib", "ignore_probe.rb"), <<~RUBY)
      module IgnoreProbe
        module_function
        def helper
          true
        end
        def self.other
          true
        end
      end
    RUBY
    path = File.join(dir, "config", "saboteur_ignore.rb")
    contents = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "a", subject: "IgnoreProbe.helper", reason: "wrong form"
        i.mutation "b", subject: "IgnoreProbe#other", reason: "wrong form"
        i.mutation "c", subject: "IgnoreProbe#helper", reason: "valid form"
        i.mutation "d", subject: "IgnoreProbe.other", reason: "valid form"
      end
    RUBY
    File.write(path, contents)

    out, err, status = doctor(dir, "--verbose")

    expect(status.exitstatus).to eq(0), err
    expect(out).to include("Warning: ignore subject IgnoreProbe.helper matches no discovered subject",
                           "Warning: ignore subject IgnoreProbe#other matches no discovered subject")
    expect(out).not_to include("ignore subject IgnoreProbe#helper", "ignore subject IgnoreProbe.other")
    expect(File.read(path)).to eq(contents)
  end

  it "limits the suite runs to --test specs, which implies --suite" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "failure_spec.rb"),
               'RSpec.describe("red") { it("fails") { expect(true).to eq(false) } }')
    out, err, status = doctor(dir, "--test", "spec/person_spec.rb")
    expect(status.exitstatus).to eq(0), err
    expect(out).to match(/unchanged suite green \(\d+ examples, [\d.]+s\)/)
  end

  it "fails plainly when the unchanged suite is red" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "failure_spec.rb"),
               'RSpec.describe("red") { it("fails") { expect(true).to eq(false) } }')
    out, err, status = doctor(dir, "--suite")
    expect(status.exitstatus).to eq(3), out
    expect(err).to include("baseline", "failed")
    expect(File).not_to exist(File.join(dir, ".saboteur"))
  end

  it "rejects run-only flags and stray arguments" do
    dir = copy_fixture("people")
    _, err, status = doctor(dir, "--incremental")
    expect(status.exitstatus).to eq(2)
    expect(err).to include("invalid option")
    _, err, status = doctor(dir, "extra")
    expect(status.exitstatus).to eq(2)
    expect(err).to include("unexpected arguments")
  end
end

RSpec.describe "doctor diagnostics", :e2e do
  def doctor_check(dir)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                   RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE,
                   "doctor", "--suite", chdir: dir)
  end

  it "reports a missing boot file as a config error" do
    dir = copy_fixture("people")
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.require = [\"missing.rb\"] }"
    end
    _, err, status = doctor_check(dir)
    expect(status.exitstatus).to eq(2)
    expect(err).to include("require file missing: missing.rb")
  end

  it "reports a broken boot file without a backtrace" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "broken.rb"), 'raise "bad boot"')
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.require = [\"broken.rb\"] }"
    end
    _, err, status = doctor_check(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("target boot failed", "bad boot")
    expect(err).not_to include("from ")
  end

  it "does not call an empty suite healthy" do
    dir = copy_fixture("people")
    FileUtils.rm_rf(File.join(dir, "spec"))
    Dir.mkdir(File.join(dir, "spec"))
    _, err, status = doctor_check(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("no tests")
  end
end

RSpec.describe "doctor failure detail", :e2e do
  def diagnose(dir)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                   RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE,
                   "doctor", "--suite", chdir: dir)
  end

  it "names a failing example and its assertion message before removing temporary output" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "bad_spec.rb"), <<~RUBY)
      RSpec.describe("diagnostic") do
        it("has a useful failure") { raise "specific assertion detail" }
      end
    RUBY
    _, err, status = diagnose(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("has a useful failure", "specific assertion detail", "bad_spec.rb")
  end

  it "reports syntax errors as a tool error without leaking a backtrace" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "syntax.rb"), "def broken(\n")
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.require = [\"syntax.rb\"] }"
    end
    _, err, status = diagnose(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("target boot failed: SyntaxError")
    expect(err).not_to include("from ")
  end

  it "reports an explicit boot exit rather than accepting its status" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "exit.rb"), "exit 0\n")
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.require = [\"exit.rb\"] }"
    end
    _, err, status = diagnose(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("target boot failed: SystemExit")
  end
end

RSpec.describe "doctor read-only and hook boundaries", :e2e do
  def check_doctor(dir)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                   RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE,
                   "doctor", "--suite", "--seed", "42", chdir: dir)
  end

  it "does not call mutation-specific before_fork callbacks" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "hooks.rb"),
               'Saboteur.hook(:before_fork) { |mutation| mutation.edits.each { raise "should not run" } }')
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.hooks = [\"hooks.rb\"] }"
    end
    _, err, status = check_doctor(dir)
    expect(status.exitstatus).to eq(0), err
  end

  it "turns a failing after_fork hook into a plain tool error" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "hooks.rb"), 'Saboteur.hook(:after_fork) { raise "hook detail" }')
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.hooks = [\"hooks.rb\"] }"
    end
    _, err, status = check_doctor(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("hook detail")
    expect(err).not_to include("from ")
  end

  it "leaves existing report and cache bytes unchanged" do
    dir = copy_fixture("people")
    cache = File.join(dir, ".saboteur")
    Dir.mkdir(cache)
    files = %w[report.json results.json coverage-old.json].map { |name| File.join(cache, name) }
    files.each { |path| File.binwrite(path, "saved\x00bytes\n") }
    before = files.to_h { |path| [path, File.binread(path)] }
    _, err, status = check_doctor(dir)
    expect(status.exitstatus).to eq(0), err
    expect(files.to_h { |path| [path, File.binread(path)] }).to eq(before)
    expect(Dir.children(cache).sort).to eq(files.map { |path| File.basename(path) }.sort)
  end

  it "rejects real instability between two freshly forked seeded runs" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "flaky_spec.rb"), <<~RUBY)
      RSpec.describe("two process instability") do
        it("changes on the second child") do
          path = File.expand_path("../pass-marker", __dir__)
          if File.exist?(path)
            raise "second seeded pass failed"
          else
            File.write(path, "first")
          end
        end
      end
    RUBY
    _, err, status = check_doctor(dir)
    expect(status.exitstatus).to eq(3)
    expect(err).to include("baseline run 2 failed", "second seeded pass failed")
  end
end
