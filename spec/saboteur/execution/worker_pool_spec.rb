# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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

  it "reports an item whose worker died as an error and carries on with the rest" do
    results = described_class.new(jobs: 2).map(%w[ok die ok]) do |item|
      Process.kill("KILL", Process.pid) if item == "die"
      { "ok" => true }
    end
    expect(results.values_at(0, 2)).to eq([{ "ok" => true }, { "ok" => true }])
    expect(results[1]).to include("error" => a_string_matching(/worker \d+ died/))
  end

  it "leaves no worker processes behind" do
    described_class.new(jobs: 3).map([1, 2, 3]) { |n| { "n" => n } }
    expect { Process.wait(-1, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
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
