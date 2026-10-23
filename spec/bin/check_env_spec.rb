# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

load File.expand_path("../../bin/check-env", __dir__)

# Guard specs for the environment gate (bin/check-env). Every hermetic
# example runs the gate against a THROWAWAY root with its own canned
# saboteur.gemspec and Gemfile.lock, so the suite's verdict never depends on
# the host checkout's real lockfile pins. Only the last example touches the
# real repository, and there a red result is the gate working, not a bug.
# The prism example is the maintainer lesson behind this gate: a stale
# RUBYLIB entry shadowed the locked prism 1.x with Ruby's bundled 0.19, and
# a whole CI run was wasted before anyone noticed.
RSpec.describe EnvCheck do
  def make_root(with_gemspec: true, with_lockfile: true)
    Dir.mktmpdir("check-env-spec-") do |dir|
      if with_gemspec
        File.write(File.join(dir, "saboteur.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "saboteur"
            spec.required_ruby_version = ">= 3.3"
            spec.add_dependency "prism", ">= 1.2", "< 2"
          end
        GEMSPEC
      end
      if with_lockfile
        File.write(File.join(dir, "Gemfile.lock"), <<~LOCK)
          GEM
            specs:
              rspec-core (3.13.6)

          BUNDLED WITH
             4.0.23
        LOCK
      end
      yield dir
    end
  end

  def good_probes
    {
      "bundle --version" => ["Bundler version 4.0.23\n", true],
      "bundle check" => ["The Gemfile's dependencies are satisfied\n", true],
      described_class::RUBY_PROBE => [RUBY_VERSION, true],
      described_class::RSPEC_PROBE => ["3.13.6", true],
      described_class::PRISM_PROBE => ["1.9.0", true]
    }
  end

  def run_check(probes: {}, **root_options)
    out = StringIO.new
    make_root(**root_options) do |root|
      commands = good_probes.merge(probes)
      runner = ->(command) { commands.fetch(command) { ["unexpected probe: #{command}", false] } }
      return [described_class.new(out: out, runner: runner, root: root).run, out.string]
    end
  end

  it "passes when the toolchain matches the repository pins" do
    status, output = run_check
    expect(status).to eq(0)
    expect(output).to include("check-env: environment ok")
    expect(output).not_to include("FAIL")
  end

  it "fails when the Ruby version does not satisfy the gemspec requirement" do
    stub_const("RUBY_VERSION", "3.2.9")
    status, output = run_check
    expect(status).to eq(1)
    expect(output).to match(/FAIL ruby - 3\.2\.9/)
  end

  it "fails when the suite's Ruby under bundle exec is not the gate's Ruby" do
    # Derived from the interpreter running the example, never a fixed
    # version: a canned value can equal the CI leg's real Ruby (a hardcoded
    # "4.0.7" passed for the wrong reason on the ruby-4.0 legs).
    different = Gem::Version.new(RUBY_VERSION).bump.to_s
    status, output = run_check(probes: { described_class::RUBY_PROBE => [different, true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL suite ruby")
  end

  it "fails on a 3.3 gate with a 4.x suite ruby" do
    stub_const("RUBY_VERSION", "3.3.9")
    status, output = run_check(probes: { described_class::RUBY_PROBE => ["4.0.7", true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL suite ruby")
  end

  it "fails on a 4.x gate with a 3.3 suite ruby" do
    stub_const("RUBY_VERSION", "4.0.7")
    status, output = run_check(probes: { described_class::RUBY_PROBE => ["3.3.9", true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL suite ruby")
  end

  it "passes the suite-ruby check when a 4.x suite ruby equals the gate" do
    stub_const("RUBY_VERSION", "4.0.7")
    status, output = run_check
    expect(status).to eq(0)
    expect(output).to include("ok   suite ruby - 4.0.7 under bundle exec (gate runs on 4.0.7)")
  end

  it "fails when Bundler cannot run" do
    status, output = run_check(probes: { "bundle --version" => ["sh: bundle: command not found\n", false] })
    expect(status).to eq(1)
    expect(output).to include("FAIL bundler")
  end

  it "fails on a Bundler major-version mismatch with BUNDLED WITH" do
    status, output = run_check(probes: { "bundle --version" => ["Bundler version 3.9.0\n", true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL bundler")
  end

  it "fails when bundle check rejects the installed gems" do
    probes = { "bundle check" => ["Bundler can't satisfy your Gemfile's dependencies.\n", false] }
    status, output = run_check(probes: probes)
    expect(status).to eq(1)
    expect(output).to include("FAIL bundle check")
  end

  it "fails when the activated rspec-core differs from the lockfile pin" do
    status, output = run_check(probes: { described_class::RSPEC_PROBE => ["3.13.5", true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL rspec-core")
  end

  it "fails when a stale RUBYLIB shadows the locked prism with the bundled 0.19" do
    status, output = run_check(probes: { described_class::PRISM_PROBE => ["0.19.0", true] })
    expect(status).to eq(1)
    expect(output).to include("FAIL prism")
  end

  it "reports locale and color settings without failing on them" do
    status, output = run_check
    expect(status).to eq(0)
    expect(output).to match(%r{ok\s+locale/color - LANG=.*default_external=})
  end

  it "fails closed when Gemfile.lock is missing, without running any probe" do
    out = StringIO.new
    make_root(with_lockfile: false) do |root|
      runner = ->(command) { raise "probe must not run without a lockfile: #{command}" }
      status = described_class.new(out: out, runner: runner, root: root).run
      expect(status).to eq(1)
    end
    expect(out.string).to include("FAIL repo layout")
    expect(out.string).to include("Gemfile.lock")
  end

  it "fails closed when the gemspec is missing, without running any probe" do
    out = StringIO.new
    make_root(with_gemspec: false) do |root|
      runner = ->(command) { raise "probe must not run without a gemspec: #{command}" }
      status = described_class.new(out: out, runner: runner, root: root).run
      expect(status).to eq(1)
    end
    expect(out.string).to include("FAIL repo layout")
    expect(out.string).to include("saboteur.gemspec")
  end

  # The one host-dependent example, on purpose: it proves the gate validates
  # THIS checkout's bundle from an unrelated working directory. On a broken
  # environment it goes red - that is the gate doing its job, and the whole
  # suite is gated on the same check anyway.
  it "passes for real from an unrelated working directory" do
    script = File.join(described_class::ROOT, "bin", "check-env")
    output, status = Open3.capture2e("ruby #{script}", chdir: Dir.tmpdir)
    expect(status).to be_success
    expect(output).to include("check-env: environment ok")
  end
end
