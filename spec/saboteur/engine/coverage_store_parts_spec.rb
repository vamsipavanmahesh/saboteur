# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

# The coverage build split into parallel parts (#741).
RSpec.describe Saboteur::Engine::CoverageStore, "in parts" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  let(:source) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:spec_files) { %w[/s/a_spec.rb /s/b_spec.rb /s/c_spec.rb] }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: spec_files) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  let(:output) { StringIO.new }

  def store(parts: 2, timeout_cap: nil)
    config = Saboteur::Config.new({}, root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(output),
                        parts: parts, timeout_cap: timeout_cap)
  end

  def part_map(*tests)
    lines = tests.to_h { |test| [1, [test]] }
    Saboteur::Selection::CoverageMap.new(lines: { source => lines }, tests: tests)
  end

  def result(map, stopped_by: nil)
    Saboteur::Execution::Supervisor::Result.new(payload: map&.to_json, exit_status: nil,
                                                stopped_by: stopped_by, detail: "stopped", runtime: 0.1,
                                                leftover_pids: [])
  end

  # Parts of [a, c] and [b]: 3 examples in all.
  def counts(total: 3, first: 2, second: 1)
    allow(integration).to receive(:example_count).with(no_args).and_return(total)
    allow(integration).to receive(:example_count).with(files: %w[/s/a_spec.rb /s/c_spec.rb]).and_return(first)
    allow(integration).to receive(:example_count).with(files: %w[/s/b_spec.rb]).and_return(second)
  end

  it "combines the parts' maps, in part order, into one map" do
    counts
    expect(supervisor).to receive(:run_many)
      .with(2, hash_including(label: "coverage child died during the map build"))
      .and_return([result(part_map("t1", "t3")), result(part_map("t2"))])

    map = store.fetch([source])

    expect(map.tests).to eq(%w[t1 t3 t2])
  end

  it "gives each part its own spec files and its own log" do
    counts
    parted = store
    allow(parted).to receive(:record)
    allow(supervisor).to receive(:run_many) do |_count, **_options, &block|
      block.call(:writer, 1)
      [result(part_map("t1", "t3")), result(part_map("t2"))]
    end

    parted.fetch([source])

    expect(parted).to have_received(:record)
      .with(:writer, [source], only: %w[/s/b_spec.rb], log: File.join(@root, ".saboteur", "coverage-build-2.log"))
  end

  it "announces the parts, prepares the heap once and ticks the progress heartbeat" do
    counts
    expect(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap).once
    expect(supervisor).to receive(:run_many)
      .with(2, hash_including(on_tick: an_instance_of(Method), timeout: 3600.0))
      .and_return([result(part_map("t1", "t3")), result(part_map("t2"))])

    store.fetch([source])

    expect(output.string).to include("building coverage map (runs the suite once, in 2 parallel parts)")
  end

  it "labels the parts heartbeat as the coverage map build" do
    counts
    diagnostics = Saboteur::Engine::Diagnostics.new(output)
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1", "t3")), result(part_map("t2"))])
    expect(diagnostics).to receive(:progress_heartbeat).with("building coverage map").and_call_original
    config = Saboteur::Config.new({}, root: @root)

    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics, parts: 2).fetch([source])
  end

  it "raises BudgetPhaseTimeout with the admitted time when a part is cut short by the budget" do
    counts
    allow(supervisor).to receive(:run_many)
      .and_return([result(part_map("t1", "t3")), result(nil, stopped_by: :timeout)])

    expect { store(timeout_cap: ->(timeout) { timeout / 2 }).fetch([source]) }
      .to raise_error(Saboteur::BudgetPhaseTimeout, /admitted 1800.0s of the 3600.0s phase timeout/)
  end

  it "keeps a part that recorded tests but no line hits" do
    counts
    dark = Saboteur::Selection::CoverageMap.new(lines: {}, tests: %w[t1 t3])
    allow(supervisor).to receive(:run_many).and_return([result(dark), result(part_map("t2"))])

    expect(store.fetch([source]).tests).to eq(%w[t1 t3 t2])
  end

  it "refuses to build when the parts do not hold the suite's examples, before running anything" do
    counts(total: 4)
    expect(supervisor).not_to receive(:run_many)

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error,
      "the coverage parts hold 3 examples but the suite has 4; " \
      "refusing to build a map from a partition that does not cover the suite"
    )
  end

  it "refuses a part that recorded no tests" do
    counts
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1", "t3")), result(part_map)])

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error, "coverage part 2 of 2 recorded no tests; refusing to build a partial map"
    )
  end

  it "refuses a combined map that holds fewer tests than the suite has examples" do
    counts
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1")), result(part_map("t2"))])

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error, "the combined coverage map holds 2 tests but the suite has 3; refusing to use a partial map"
    )
  end

  it "fails when one part was stopped, instead of using the others" do
    counts
    allow(supervisor).to receive(:run_many)
      .and_return([result(part_map("t1", "t3")), result(nil, stopped_by: :timeout)])

    expect { store.fetch([source]) }.to raise_error(Saboteur::Error, /coverage map build stopped/)
  end

  it "keeps the single child build when the suite has fewer files than parts" do
    allow(integration).to receive(:test_files).and_return(%w[/s/a_spec.rb])
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))
    expect(supervisor).not_to receive(:run_many)

    expect(store.fetch([source]).tests).to eq(%w[t1])
  end

  it "keeps the single child build by default and never counts examples or deals parts" do
    expect(integration).not_to receive(:example_count)
    expect(Saboteur::Engine::SuitePartition).not_to receive(:parts)
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))

    expect(store(parts: 1).fetch([source]).tests).to eq(%w[t1])
  end

  it "treats a parts value below 2 as the single child build" do
    expect(Saboteur::Engine::SuitePartition).not_to receive(:parts)
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))

    expect(store(parts: 0).fetch([source]).tests).to eq(%w[t1])
  end

  it "gives each part child its own TEST_ENV_NUMBER, empty for the first" do
    counts
    seen = []
    allow(supervisor).to receive(:run_many) do |_count, **, &block|
      saved = ENV.fetch("TEST_ENV_NUMBER", nil)
      2.times do |index|
        allow_any_instance_of(described_class).to receive(:record) { seen << ENV.fetch("TEST_ENV_NUMBER", nil) }
        block.call(:writer, index)
      end
      ENV["TEST_ENV_NUMBER"] = saved
      [result(part_map("t1", "t3")), result(part_map("t2"))]
    end

    store.fetch([source])

    expect(seen).to eq(["", "2"])
  end

  it "reports a file list the suite cannot honor as a usage error, not a crash" do
    allow(integration).to receive(:example_count).and_raise(ArgumentError, "no example group in: /s/a_spec.rb")
    expect(supervisor).not_to receive(:run_many)

    expect { store.fetch([source]) }
      .to raise_error(Saboteur::ConfigError, "no example group in: /s/a_spec.rb")
  end

  it "reports an unusable partition request as a usage error too" do
    allow(Saboteur::Engine::SuitePartition).to receive(:parts).and_raise(ArgumentError, "bad parts")

    expect { store.fetch([source]) }.to raise_error(Saboteur::ConfigError, "bad parts")
  end

  describe "recording one part" do
    it "runs the whole suite, with no files argument, when no part is given" do
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(recorder).to receive(:result).and_return(part_map("t1"))
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      expect(integration).to receive(:run_all).with(recorder).and_return(true)
      whole = store
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(whole).to receive(:exit!)

      whole.send(:record, StringIO.new, [source])
    end

    it "runs only that part's files and writes to the part's log" do
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(recorder).to receive(:result).and_return(part_map("t1"))
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      expect(integration).to receive(:run_all).with(recorder, files: %w[/s/b_spec.rb]).and_return(true)
      part_store = store
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(part_store).to receive(:exit!)
      log = File.join(@root, "logs", "part.log")

      part_store.send(:record, StringIO.new, [source], only: %w[/s/b_spec.rb], log: log)

      expect($stdout).to have_received(:reopen).with(log, "w")
      expect(File.directory?(File.dirname(log))).to be(true)
    end
  end

  describe "a failed build" do
    def write_log(name, lines)
      FileUtils.mkdir_p(File.join(@root, ".saboteur"))
      File.write(File.join(@root, ".saboteur", name), lines.join("\n") << "\n")
    end

    def failed(message = "the unchanged suite failed while building coverage. Fix the suite, then run again.")
      Saboteur::Execution::Supervisor::Result.new(payload: JSON.generate(error: message), exit_status: nil,
                                                  stopped_by: nil, detail: nil, runtime: 0.1, leftover_pids: [])
    end

    def died_without_report
      Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: nil,
                                                  detail: nil, runtime: 0.1, leftover_pids: [])
    end

    it "shows the last 60 lines of every failed part, each under its part" do
      counts
      write_log("coverage-build-1.log", (1..100).map { |n| "first #{n}" })
      write_log("coverage-build-2.log", (1..100).map { |n| "second #{n}" })
      allow(supervisor).to receive(:run_many).and_return([failed, failed])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
        message = error.message
        expect(message).to include("part 1 of 2: ", "part 2 of 2: ",
                                   "the last 60 lines of .saboteur/coverage-build-1.log")
        expect(message).to include("| first 41\n", "| first 100", "| second 41\n", "| second 100")
        expect(message).not_to include("first 40\n", "second 40\n")
        expect(message).to include("| first 100\npart 2 of 2: ")
      }
    end

    it "names only the parts that failed" do
      counts
      write_log("coverage-build-2.log", %w[boom])
      allow(supervisor).to receive(:run_many).and_return([result(part_map("t1", "t3")), failed])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
        expect(error.message).to include("part 2 of 2: ", "| boom")
        expect(error.message).not_to include("part 1 of 2")
      }
    end

    it "shows the output of a part that died without reporting" do
      counts
      write_log("coverage-build-1.log", %w[segfault-ish])
      allow(supervisor).to receive(:run_many).and_return([died_without_report, result(part_map("t2"))])

      expect do
        store.fetch([source])
      end.to raise_error(Saboteur::Error,
                         /before reporting; its output is in .*coverage-build-1.log\n.*\n\| segfault-ish/m)
    end

    it "shows the output of a build that is not in parts" do
      write_log("coverage-build.log", (1..70).map { |n| "line #{n}" })
      allow(supervisor).to receive(:run).and_return(failed)

      expect { store(parts: 1).fetch([source]) }
        .to raise_error(Saboteur::Error,
                        %r{Fix the suite.*the last 60 lines of \.saboteur/coverage-build\.log:\n| line 11\n}m)
    end

    it "escapes control characters, strips colors and marks every line so none can be a workflow command" do
      counts
      write_log("coverage-build-1.log", ["::error::forged", "\e[31mred\e[0m", "bell\a\u0085end", "\e[mreset", "plain"])
      allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
        expect(error.message).to include("\n| \\x3a:error::forged\n", "\n| red\n", "\n| bell\\x07\\x85end\n",
                                         "\n| reset\n")
        expect(error.message).not_to match(/^::/)
        expect(error.message).not_to include("\e")
      }
    end

    describe "workflow commands in a child's output" do
      let(:hostile) do
        ["::error::x", "   ::error::x", "\t::error::x", "\u00a0::warning::x", "\u2003 ::notice::x",
         "::stop-commands::tok", "##[error]x", "see ##[warning]y here", " ##[group]z"]
      end

      def commands_in(message)
        message.lines.select do |line|
          line.sub(/\A[[:space:]]+/, "").start_with?("::") || line.include?("##[")
        end
      end

      it "leaves none in the log tail" do
        counts
        write_log("coverage-build-1.log", hostile)
        allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

        expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
          expect(commands_in(error.message)).to eq([])
          expect(error.message.lines.count { |line| line.start_with?("| ") }).to eq(hostile.size)
        }
      end

      it "leaves none in the error the child reported, on any of its lines" do
        counts
        allow(supervisor).to receive(:run_many)
          .and_return([failed(hostile.join("\n")), failed(hostile.reverse.join("\n"))])

        expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
          expect(commands_in(error.message)).to eq([])
          expect(error.message.scan("x3a").size).to eq(10)
        }
      end

      it "breaks the token itself, so the line is safe even if it is not at the start" do
        counts
        allow(supervisor).to receive(:run_many)
          .and_return([failed("::error::x"), failed("\u00a0::warning::x\n##[error]y")])

        expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
          expect(error.message).to include("failed: \\x3a:error::x", "failed: \u00a0\\x3a:warning::x\n| ##\\x5berror]y")
        }
      end

      it "keeps an rspec failure line with colons and brackets readable" do
        counts
        lines = ["Failure/Error: expect(map).to be_a(Saboteur::Selection::CoverageMap)",
                 "  # ./spec/saboteur/a_spec.rb:12:in `block (2 levels) in <top (required)>'",
                 "rspec ./spec/saboteur/a_spec.rb[1:2] # a [slow] ::example", "  expected: [1, 2]"]
        write_log("coverage-build-1.log", lines)
        allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

        expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
          expect(error.message).to end_with(lines.map { |line| "| #{line}" }.join("\n"))
        }
      end
    end

    it "cuts a very long line to 300 characters and leaves a 300-character line whole" do
      counts
      long = ("a".."z").cycle.first(1000).join
      write_log("coverage-build-1.log", [long, "z" * 300])
      allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
        expect(error.message).to include("| #{long[0, 300]}...\n", "| #{'z' * 300}")
        expect(error.message).not_to include("#{'z' * 300}...")
      }
    end

    it "reads only the end of a large log and drops the line the cut lands in" do
      counts
      write_log("coverage-build-1.log", Array.new(5) { |n| "#{n}#{'x' * 19_999}" })
      allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error) { |error|
        expect(error.message).to include("the last 3 lines of")
        expect(error.message).to match(/\| 2x+\.\.\.\n\| 3x+\.\.\.\n\| 4x+\.\.\.\z/)
      }
    end

    it "shows a log of exactly the byte limit whole" do
      counts
      write_log("coverage-build-1.log", ["first", "x" * 65_529])
      expect(File.size(File.join(@root, ".saboteur", "coverage-build-1.log"))).to eq(65_536)
      allow(supervisor).to receive(:run_many).and_return([failed, result(part_map("t2"))])

      expect { store.fetch([source]) }.to raise_error(Saboteur::Error, /the last 2 lines of.*\n| first\n/m)
    end

    it "adds nothing for an empty log" do
      counts
      write_log("coverage-build-1.log", [])
      File.write(File.join(@root, ".saboteur", "coverage-build-1.log"), "")
      allow(supervisor).to receive(:run_many).and_return([failed("the suite broke"), result(part_map("t2"))])

      expect { store.fetch([source]) }
        .to raise_error(Saboteur::Error, "part 1 of 2: coverage map build failed: the suite broke")
    end

    describe "the error the child reported" do
      def build_error(message)
        counts
        allow(supervisor).to receive(:run_many).and_return([failed(message), result(part_map("t2"))])
        store.fetch([source])
      rescue Saboteur::Error => e
        e.message
      end

      it "cannot start a workflow command line, whatever it contains" do
        message = build_error("first\n::error::forged\r::warning::also\n\n::add-mask::x\u0085::notice::y")

        expect(message).not_to match(/^::/)
        expect(message).not_to match(/[\r\u0085]/)
        expect(message.lines.size).to eq(4)
        expect(message).to include("failed: first\n| \\x3a:error::forged\\x0d::warning::also\n| \n",
                                   "| \\x3a:add-mask::x\\x85::notice::y")
      end

      it "escapes control characters and colors on its first line too" do
        message = build_error("\e[31m::error::boom\a\e[0m")

        expect(message).to eq("part 1 of 2: coverage map build failed: \\x3a:error::boom\\x07")
        expect(message).not_to match(/^::/)
      end

      it "cuts a long first line, keeps a 300-character one whole and bounds the lines after it" do
        long = ("a".."z").cycle.first(400).join
        message = build_error(([long] + Array.new(80) { |n| "l#{n}" }).join("\n"))

        expect(message).to include("failed: #{long[0, 300]}...\n")
        expect(build_error("z" * 300)).to end_with(": #{'z' * 300}")
        expect(message.lines.size).to eq(61)
        expect(message).to include("| l59")
        expect(message).not_to include("l60")
      end

      it "survives an error that is not a string" do
        expect(build_error(42)).to eq("part 1 of 2: coverage map build failed: 42")
      end
    end

    it "keeps the original message when there is no log to read" do
      counts
      allow(supervisor).to receive(:run_many).and_return([failed("the suite broke"), result(part_map("t2"))])

      expect { store.fetch([source]) }
        .to raise_error(Saboteur::Error, "part 1 of 2: coverage map build failed: the suite broke")
    end

    it "still raises a budget stop at once, even when another part failed" do
      counts
      write_log("coverage-build-1.log", %w[boom])
      allow(supervisor).to receive(:run_many).and_return([failed, result(nil, stopped_by: :timeout)])

      expect { store(timeout_cap: ->(timeout) { timeout / 2 }).fetch([source]) }
        .to raise_error(Saboteur::BudgetPhaseTimeout)
    end
  end
end
