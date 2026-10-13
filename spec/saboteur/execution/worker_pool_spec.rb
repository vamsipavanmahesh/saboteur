# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "timeout"

RSpec.describe Saboteur::Execution::WorkerPool do
  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  it "returns each item's result in item order, whatever order workers finish in" do
    results = described_class.new(jobs: 3).map([3, 1, 2, 0]) do |n|
      sleep(n * 0.05)
      { "square" => n * n, "worker" => ENV.fetch("SABOTEUR_WORKER") }
    end
    expect(results.map { |r| r["square"] }).to eq([9, 1, 4, 0])
  end

  it "runs items at the same time on several workers" do
    started = monotonic
    described_class.new(jobs: 4).map([0.3] * 4) do |seconds|
      sleep seconds
      {}
    end
    expect(monotonic - started).to be < 0.9
  end

  it "reports each result on arrival, before the worker gets more work" do
    arrivals = []
    pool = described_class.new(jobs: 2, on_result: ->(item, row) { arrivals << [item, row["square"]] })
    results = pool.map([1, 2, 3]) { |n| { "square" => n * n } }
    expect(results.map { |r| r["square"] }).to eq([1, 4, 9])
    expect(arrivals.sort).to eq([[0, 1], [1, 4], [2, 9]])
  end

  it "stops handing out work when the arrival callback raises" do
    Dir.mktmpdir do |dir|
      log = File.join(dir, "ran")
      pool = described_class.new(jobs: 2, on_result: ->(_item, _row) { raise Saboteur::CanaryTripped, "trip" })
      expect do
        pool.map([0.01, 0.01, 0.01, 0.01]) do |seconds|
          sleep seconds
          File.open(log, "a") { |f| f.puts(seconds) }
          {}
        end
      end.to raise_error(Saboteur::CanaryTripped, "trip")
      expect(File.read(log).split.size).to be < 4
    end
  end

  it "numbers its workers the way Rails parallel test databases expect" do
    numbers = described_class.new(jobs: 2).map([0.1, 0.1]) do |seconds|
      sleep seconds
      { "n" => ENV.fetch("TEST_ENV_NUMBER") }
    end
    expect(numbers.map { |r| r["n"] }.sort).to eq(["", "2"])
  end

  it "hands the biggest items out first when given weights" do
    ran = []
    described_class.new(jobs: 1).map(%w[small big medium], weights: [1, 9, 5]) do |name|
      ran << name
      {}
    end
    expect(ran).to eq(%w[big medium small])
  end

  it "routes a dead worker's synthetic error row through on_result, so the canary can trip" do
    dir = Dir.mktmpdir
    sentinel = File.join(dir, "sentinel")
    File.write(sentinel, "watch me")
    pool = described_class.new(jobs: 2, on_result: lambda { |_item, _row|
      raise Saboteur::CanaryTripped, "canary: watched file vanished" unless File.exist?(sentinel)
    })
    expect do
      pool.map(["die"]) do |_item|
        FileUtils.rm_f(sentinel)
        Process.kill("KILL", Process.pid)
      end
    end.to raise_error(Saboteur::CanaryTripped, /watched file vanished/)
  end

  it "reports an item whose worker died as an error and carries on with the rest" do
    results = described_class.new(jobs: 2).map(%w[ok die ok]) do |item|
      Process.kill("KILL", Process.pid) if item == "die"
      { "ok" => true }
    end
    expect(results.values_at(0, 2)).to eq([{ "ok" => true }, { "ok" => true }])
    expect(results[1]).to include("error" => a_string_matching(/worker \d+ died/))
  end

  # A dead worker must leave a reason, or 4,000 mutants show as "E" with
  # nothing to go on (first human-essentials run at --jobs 6).
  it "says what a worker raised when it crashed" do
    results = described_class.new(jobs: 2).map(%w[ok crash]) do |item|
      raise NoMemoryError, "boom" if item == "crash"

      { "ok" => true }
    end
    expect(results[1]["error"]).to match(/\Aworker \d+ crashed: NoMemoryError: boom \(.*worker_pool_spec\.rb:\d+/)
  end

  it "says which signal killed a worker" do
    results = described_class.new(jobs: 2).map(%w[ok die ok]) do |item|
      Process.kill("KILL", Process.pid) if item == "die"
      { "ok" => true }
    end
    expect(results[1]["error"]).to match(/\Aworker \d+ died \(signal KILL\)/)
  end

  it "stops with the reason when workers keep dying before their first item" do
    failing = described_class.new(jobs: 2, on_start: ->(_) { raise "no database" })
    expect { failing.map([1, 2, 3, 4, 5]) { |n| { "n" => n } } }
      .to raise_error(Saboteur::Error, /\Aworkers keep failing to start: worker \d+ crashed: RuntimeError: no database/)
  end

  # Each example is bounded by a timeout: a regression must fail, not hang.
  it "notices a dead worker even when its child still holds the result pipe" do
    results = nil
    Timeout.timeout(20) do
      results = described_class.new(jobs: 2).map(%w[orphan ok]) do |item|
        if item == "orphan"
          fork { sleep 30 } # keeps the worker's pipes open, as a stray child would
          Process.kill("KILL", Process.pid)
        end
        { "ok" => item }
      end
    end
    expect(results[0]).to include("error" => a_string_matching(/died/))
    expect(results[1]).to eq("ok" => "ok")
  rescue Timeout::Error
    raise "parent hung waiting on a dead worker"
  end

  it "does not let a worker inherit the parent's list of live trees" do
    Saboteur::Execution::Supervisor.live[999_999] = :sibling
    seen = described_class.new(jobs: 2).map([1, 2]) do |_|
      { "inherited" => Saboteur::Execution::Supervisor.live.key?(999_999) }
    end
    expect(seen.map { |r| r["inherited"] }).to eq([false, false])
  ensure
    Saboteur::Execution::Supervisor.live.delete(999_999)
  end

  it "turns an unreadable result into an error for that item" do
    results = described_class.new(jobs: 2).map([1, 2]) { |n| n == 1 ? { "bad" => Float::NAN } : { "n" => n } }
    expect(results[0]).to include("error")
    expect(results[1]).to eq("n" => 2)
  end

  it "leaves no worker processes behind" do
    left = children_left_by { described_class.new(jobs: 3).map([1, 2, 3]) { |n| { "n" => n } } }
    expect(left).to be_empty
  end

  it "calls on_start in each worker, with its number, before its first item" do
    started = described_class.new(jobs: 2, on_start: ->(number) { ENV["STARTED_AS"] = number.to_s })
                             .map([0.1, 0.1]) do |seconds|
      sleep seconds
      { "started_as" => ENV.fetch("STARTED_AS"), "worker" => ENV.fetch("SABOTEUR_WORKER") }
    end
    expect(started.map { |r| r["started_as"] }).to eq(started.map { |r| r["worker"] })
  end

  it "runs inline, without forking, for one job" do
    pids = described_class.new(jobs: 1).map([1, 2]) { |_| { "pid" => Process.pid } }
    expect(pids.map { |r| r["pid"] }.uniq).to eq([Process.pid])
  end
end
