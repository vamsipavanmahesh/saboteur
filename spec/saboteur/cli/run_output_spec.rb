# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"

RSpec.describe Saboteur::CLI::RunOutput do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the report announcement and the stdout redirect, moved out of CLI itself" do
    owned = %i[announce_reports stdout_on_stderr]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end

  # Behavior pins (#841): called here so the dogfood run that selects this
  # spec by name sees these methods execute.
  describe "#announce_reports" do
    let(:out) { StringIO.new }
    let(:cli) { Saboteur::CLI.new([], out: out) }

    around do |example|
      Dir.mktmpdir do |dir|
        @root = File.realpath(dir)
        example.run
      end
    end

    before { allow(cli).to receive(:config).and_return(instance_double(Saboteur::Config, root: @root)) }

    it "prints nothing when no report was written" do
      cli.send(:announce_reports, [[nil, "JSON"], [nil, "HTML"]])
      cli.send(:announce_reports, [])

      expect(out.string).to eq("")
    end

    it "names written reports relative to the root, after a blank line" do
      cli.send(:announce_reports, [[File.join(@root, ".saboteur", "report.json"), "JSON"], [nil, "HTML"],
                                   [File.join(@root, "out.html"), "HTML"]])

      expect(out.string).to eq("\nReports: .saboteur/report.json (JSON), out.html (HTML)\n")
    end

    it "keeps a path outside the root as given" do
      cli.send(:announce_reports, [["/elsewhere/report.json", "JSON"]])

      expect(out.string).to eq("\nReports: /elsewhere/report.json (JSON)\n")
    end
  end

  describe "#stdout_on_stderr" do
    # A named stand-in for an IO that logs dup, reopen and close to a shared list.
    let(:fake_io_class) do
      Class.new do
        attr_reader :name

        def initialize(name, log) = (@name = name) && (@log = log)
        def dup = self.class.new("saved", @log).tap { @log << [:dup, name] }
        def reopen(other) = @log << [:reopen, name, other.name]
        def close = @log << [:close, name]
        def write(*) = 0
      end
    end

    it "points stdout at stderr for the block, then restores and closes the saved descriptor" do
      log = []
      real = [$stdout, $stderr]
      during = nil
      begin
        $stdout = fake_io_class.new("out", log)
        $stderr = fake_io_class.new("err", log)
        value = Saboteur::CLI.new([]).send(:stdout_on_stderr) do
          during = log.dup
          7
        end
      ensure
        $stdout, $stderr = real
      end

      expect(value).to eq(7)
      expect(during).to eq([[:dup, "out"], [:reopen, "out", "err"]])
      expect(log).to eq([[:dup, "out"], [:reopen, "out", "err"], [:reopen, "out", "saved"], [:close, "saved"]])
    end

    it "lets the original error through, and touches nothing, when stdout cannot be duplicated" do
      log = []
      broken = fake_io_class.new("out", log)
      broken.define_singleton_method(:dup) { raise IOError, "no descriptor" }
      broken.define_singleton_method(:reopen) { |_other| log << :reopened }
      real = [$stdout, $stderr]
      ran = false
      begin
        $stdout = broken
        $stderr = fake_io_class.new("err", log)
        expect { Saboteur::CLI.new([]).send(:stdout_on_stderr) { ran = true } }
          .to raise_error(IOError, "no descriptor")
      ensure
        $stdout, $stderr = real
      end

      expect(ran).to be(false)
      expect(log).to eq([])
    end

    def wait_or_kill(pid)
      Timeout.timeout(30) { Process.wait2(pid).last }
    rescue Timeout::Error
      Process.kill("KILL", pid)
      Process.wait(pid)
      raise
    end

    def run_in_child
      Dir.mktmpdir do |dir|
        out_path = File.join(dir, "out")
        err_path = File.join(dir, "err")
        pid = fork do
          $stdout.reopen(out_path, "w")
          $stderr.reopen(err_path, "w")
          $stdout.sync = $stderr.sync = true
          yield
          exit!(0)
        rescue StandardError
          exit!(1)
        end
        status = wait_or_kill(pid)
        [File.read(out_path), File.read(err_path), status.exitstatus]
      end
    end

    it "sends stdout to stderr inside the block and restores it afterwards" do
      cli = Saboteur::CLI.new([])
      out, err, status = run_in_child do
        cli.send(:stdout_on_stderr) { $stdout.puts "inside" }
        $stdout.puts "after"
      end

      expect([out, err, status]).to eq(["after\n", "inside\n", 0])
    end

    it "returns the block's value and restores stdout when the block raises" do
      cli = Saboteur::CLI.new([])
      out, err, status = run_in_child do
        value = cli.send(:stdout_on_stderr) { 42 }
        begin
          cli.send(:stdout_on_stderr) { raise "boom" }
        rescue RuntimeError
          $stdout.puts "restored #{value}"
        end
      end

      expect([out, err, status]).to eq(["restored 42\n", "", 0])
    end
  end
end
