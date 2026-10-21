# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"
require "rspec/core/sandbox"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Integration::RSpec, "load failure text and baseline plumbing" do
  def build(config = {}) = described_class.new(Saboteur::Config.new(config, root: Dir.pwd))

  describe "#load_failure_message" do
    let(:integration) { build }

    before { allow(Saboteur::EnvironmentHints).to receive(:all).and_return([]) }

    it "names every failed file when there are few and omits the overflow line" do
      message = integration.send(:load_failure_message, %w[a.rb b.rb])
      expect(message).to start_with("rspec quit while loading spec files: 2 failed to load:\n  a.rb\n  b.rb\n" \
                                    "Exclude the broken")
      expect(message).not_to include("more")
    end

    it "shows five files and counts the rest" do
      files = (1..8).map { |i| "f#{i}.rb" }
      message = integration.send(:load_failure_message, files)
      expect(message).to include("8 failed to load:\n  f1.rb\n  f2.rb\n  f3.rb\n  f4.rb\n  f5.rb\n  ... and 3 more\n")
      expect(message).not_to include("f6.rb")
    end

    it "shows no overflow line at exactly five files" do
      expect(integration.send(:load_failure_message, (1..5).map { |i| "f#{i}.rb" })).not_to include("more")
    end

    it "omits the file list when nothing failed and still gives the way out" do
      message = integration.send(:load_failure_message, [])
      expect(message).to start_with("rspec quit while loading spec files\nExclude the broken")
      expect(message).to include('c.rspec_args = ["--exclude-pattern", "spec/dummy/**/*_spec.rb"]')
      expect(message).to include("or name the suite with --test.")
      expect(message).to include('see README "Rails engines and dummy apps".')
      expect(message).not_to include("Suspect")
    end

    it "appends environment hints joined with semicolons" do
      allow(Saboteur::EnvironmentHints).to receive(:all).and_return(%w[one two])
      expect(integration.send(:load_failure_message, [])).to end_with("\nSuspect: one; two.")
    end

    it "appends the coverage suspect text only for a coverage collision" do
      message = integration.send(:load_failure_message, [], "Coverage measurement is already setup")
      expect(message).to end_with("docs/recipes/README.md#simplecov.")
      expect(message).to include("\nSuspect: your suite starts its own Coverage (saboteur starts one itself). " \
                                 "Guard it - if ENV[\"COVERAGE\"]")
      expect(integration.send(:load_failure_message, [], "unrelated")).not_to include("Coverage")
    end
  end

  describe "#coverage_suspect?" do
    let(:integration) { build }

    it "matches the double start text, a gem frame, or a start call, case-insensitively" do
      expect(integration.send(:coverage_suspect?, "COVERAGE MEASUREMENT IS ALREADY SETUP")).to be(true)
      expect(integration.send(:coverage_suspect?, "x/simplecov/lib/a.rb:12")).to be(true)
      expect(integration.send(:coverage_suspect?, "SingleCov.setup :rspec")).to be(true)
    end

    it "is exactly false for no capture, unrelated text, or a bare file name" do
      expect(integration.send(:coverage_suspect?, nil)).to be(false)
      expect(integration.send(:coverage_suspect?, "boom")).to be(false)
      expect(integration.send(:coverage_suspect?, "simplecov_config_spec.rb")).to be(false)
    end
  end

  describe "run and baseline plumbing" do
    let(:rspec_config) { instance_double(RSpec::Core::Configuration, :order= => nil, :fail_fast= => nil) }
    let(:listener) do
      instance_double(described_class::Listener, failed: failed, executed: %w[e1 e2], runtime: 1.5,
                                                 failure_classes: { "f" => "C" }, failure_messages: { "f" => "m" },
                                                 failure_details: { "f" => "d" })
    end
    let(:failed) { [] }

    before do
      allow(described_class::Listener).to receive(:new).and_return(listener)
    end

    def wire(integration, passed)
      allow(integration).to receive_messages(configuration: rspec_config, execute: passed)
    end

    it "run_baseline sets the seed, keeps going past failures, and passes every field through" do
      integration = build
      wire(integration, true)
      result = integration.run_baseline(seed: 42, files: ["a_spec.rb"])
      expect(rspec_config).to have_received(:order=).with("rand:42")
      expect(rspec_config).to have_received(:fail_fast=).with(false)
      expect(integration).to have_received(:execute).with(listener, log_phase: true, files: ["a_spec.rb"])
      expect(result).to have_attributes(passed: true, failed_ids: [], executed_ids: %w[e1 e2], runtime: 1.5,
                                        failure_classes: { "f" => "C" }, failure_messages: { "f" => "m" },
                                        failure_details: { "f" => "d" })
    end

    context "when the listener saw a failure" do
      let(:failed) { ["x"] }

      it "fails the baseline even if execute reported success, and the same for run" do
        integration = build
        wire(integration, true)
        allow(integration).to receive_messages(narrow_to: nil, order_by: nil)
        expect(integration.run_baseline(seed: 1).passed).to be(false)
        expect(integration.run(["x"]).passed).to be(false)
      end
    end

    it "fails the baseline when execute fails with a clean listener" do
      integration = build
      wire(integration, false)
      expect(integration.run_baseline(seed: 1).passed).to be(false)
    end

    it "run uses fail-fast 1 normally and no fail-fast in matrix mode, with all result fields" do
      integration = build
      wire(integration, true)
      allow(integration).to receive_messages(narrow_to: nil, order_by: nil)
      result = integration.run(["x"])
      expect(rspec_config).to have_received(:fail_fast=).with(1)
      expect(result).to have_attributes(passed: true, executed_ids: %w[e1 e2], runtime: 1.5,
                                        failure_classes: { "f" => "C" }, failure_messages: { "f" => "m" },
                                        failure_details: { "f" => "d" })
      matrix = build("matrix" => true)
      wire(matrix, true)
      allow(matrix).to receive_messages(narrow_to: nil, order_by: nil)
      matrix.run(["x"])
      expect(rspec_config).to have_received(:fail_fast=).with(false)
    end

    it "run_all falls back to the configured seed, and never stops at the first failure" do
      integration = build("seed" => 9)
      wire(integration, true)
      integration.run_all(:recorder, files: ["a"])
      expect(rspec_config).to have_received(:order=).with("rand:9")
      expect(rspec_config).to have_received(:fail_fast=).with(false)
      expect(described_class::Listener).to have_received(:new).with(:recorder)
      expect(integration).to have_received(:execute).with(listener, log_phase: true, files: ["a"])
      integration.run_all(:recorder, seed: 5)
      expect(rspec_config).to have_received(:order=).with("rand:5")
    end
  end

  describe "#setup with spec files that break on load" do
    def setup_in_sandbox(files, config = { "tests" => ["spec"] })
      outcome = {}
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        files.each { |name, body| File.write(File.join(dir, "spec", name), body) }
        Dir.chdir(File.realpath(dir)) do
          RSpec::Core::Sandbox.sandboxed do |rc|
            out = StringIO.new
            rc.output_stream = out
            rc.error_stream = out
            outcome = capture_setup(config, out)
          end
        end
      end
      outcome
    end

    def capture_setup(config, sink)
      integration = described_class.new(Saboteur::Config.new(config, root: Dir.pwd))
      original = [$stdout, $stderr]
      $stdout = $stderr = sink
      error = nil
      begin
        integration.setup
      rescue Saboteur::Error => e
        error = e
      ensure
        $stdout, $stderr = original
      end
      { error: error, out: sink.string, order: integration.send(:configuration).seed }
    end

    it "raises with the failed file named and prints the suite error" do
      outcome = setup_in_sandbox("boom_spec.rb" => "raise 'kaboom from load'\n")
      expect(outcome[:error].message).to include("rspec quit while loading spec files: 1 failed to load:")
      expect(outcome[:error].message).to include("boom_spec.rb")
      expect(outcome[:out]).to include("kaboom from load")
      expect(outcome[:out]).not_to include("No examples found.")
    end

    it "prints the suite error unfiltered when verbose is set" do
      outcome = setup_in_sandbox({ "boom_spec.rb" => "raise 'kaboom from load'\n" },
                                 { "tests" => ["spec"], "verbose" => true })
      expect(outcome[:out]).to include("No examples found.")
    end

    it "raises with the exit status when a spec file calls exit at load" do
      outcome = setup_in_sandbox("exit_spec.rb" => "exit 3\n")
      expect(outcome[:error].message).to eq("a spec file called exit while loading (status 3)")
    end

    it "orders examples with the configured seed after a clean load" do
      outcome = setup_in_sandbox({ "ok_spec.rb" => "RSpec.describe('ok') { it('a') { } }\n" },
                                 { "tests" => ["spec"], "seed" => 7 })
      expect(outcome[:error]).to be_nil
      expect(outcome[:order]).to eq(7)
    end

    it "orders examples with seed 1 when no seed is configured" do
      outcome = setup_in_sandbox("ok_spec.rb" => "RSpec.describe('ok') { it('a') { } }\n")
      expect(outcome[:error]).to be_nil
      expect(outcome[:order]).to eq(1)
    end
  end
end
