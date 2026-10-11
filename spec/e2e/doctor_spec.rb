# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "doctor", :e2e do
  def doctor(dir, *arguments)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                   RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE,
                   "doctor", *arguments, chdir: dir)
  end

  it "checks the environment and two seeded baselines without writing caches or reports" do
    dir = copy_fixture("people")
    out, err, status = doctor(dir, "--seed", "42")
    expect(status.exitstatus).to eq(0), err
    expect(out).to include("Ruby:", "Coverage: suspended", "Integration: rspec", "passed twice", "seed 42")
    expect(File).not_to exist(File.join(dir, ".saboteur"))
  end

  it "fails plainly when the unchanged suite is red" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "failure_spec.rb"),
               'RSpec.describe("red") { it("fails") { expect(true).to eq(false) } }')
    out, err, status = doctor(dir)
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
                   "doctor", chdir: dir)
  end

  it "reports a missing boot file as a config error" do
    dir = copy_fixture("people")
    File.open(File.join(dir, ".saboteur.yml"), "a") { |file| file.puts "require: [missing.rb]" }
    _, err, status = doctor_check(dir)
    expect(status.exitstatus).to eq(2)
    expect(err).to include("require file missing: missing.rb")
  end

  it "reports a broken boot file without a backtrace" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "broken.rb"), 'raise "bad boot"')
    File.open(File.join(dir, ".saboteur.yml"), "a") { |file| file.puts "require: [broken.rb]" }
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
