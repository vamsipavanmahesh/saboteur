# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  it "uses defaults without a config file" do
    config = described_class.load(root: @root)
    expect(config.to_h.values_at("integration", "timeout_factor", "timeout_min", "jobs", "reeval"))
      .to eq(["rspec", 3.0, 5.0, 1, "nesting"])
  end

  it "reads .saboteur.yml and lets CLI overrides win" do
    write(".saboteur.yml", "timeout_factor: 4\njobs: 1\nreeval: nesting\n")
    config = described_class.load(root: @root, overrides: { timeout_factor: 2.5, since: nil })
    expect([config["timeout_factor"], config["reeval"], config["since"]]).to eq([2.5, "nesting", nil])
  end

  it "resolves include and exclude globs to real paths of .rb files" do
    write("lib/a.rb", "")
    write("lib/b.rb", "")
    write("lib/version.rb", "")
    write("lib/notes.txt", "")
    config = described_class.new({ "include" => ["lib/**/*"], "exclude" => ["lib/version.rb"] }, root: @root)
    expect(config.included_files).to eq(%w[a.rb b.rb].map { |f| File.join(@root, "lib", f) })
  end

  it "names include and exclude patterns that match no file, so a stale path is never silent" do
    write("lib/a.rb", "")
    config = described_class.new({ "include" => ["lib/**/*.rb", "app/**/*.rb"],
                                   "exclude" => ["lib/a.rb", "lib/moved.rb"] }, root: @root)
    expect(config.unmatched_patterns).to eq(["include: app/**/*.rb", "exclude: lib/moved.rb"])
  end

  it "rejects unknown keys, bad values and bad arid patterns" do
    expect { described_class.new({ "timeout" => 1 }) }.to raise_error(Saboteur::Error, /unknown config key/)
    expect { described_class.new({ "jobs" => "many" }) }.to raise_error(Saboteur::Error, /invalid config value/)
    expect { described_class.new({ "jobs" => 0 }) }.to raise_error(Saboteur::Error, /jobs/)
    expect { described_class.new({ "arid" => ["("] }) }.to raise_error(Saboteur::Error, /arid/)
    expect { described_class.new({ "reeval" => "eval" }) }.to raise_error(Saboteur::Error, /reeval/)
  end

  it "reports YAML errors with the file name" do
    write(".saboteur.yml", "include: [\n")
    expect { described_class.load(root: @root) }.to raise_error(Saboteur::Error, /\.saboteur\.yml/)
  end

  it "expands paths relative to the root" do
    expect(described_class.new({}, root: @root).path("ignore_file")).to eq(File.join(@root, ".saboteur-ignore.yml"))
  end
end

RSpec.describe Saboteur::Config, "details" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, content)
    File.join(@root, path).tap { |full| File.write(full, content) }
  end

  it "reads the config file it is given instead of .saboteur.yml" do
    write(".saboteur.yml", "jobs: 2\n")
    custom = write("custom.yml", "jobs: 3\n")
    expect(described_class.load(root: @root, path: custom)["jobs"]).to eq(3)
  end

  it "treats an empty config file as defaults and rejects one that is not a mapping" do
    write(".saboteur.yml", "")
    expect(described_class.load(root: @root)["jobs"]).to eq(1)
    write(".saboteur.yml", "- a\n")
    expect { described_class.load(root: @root) }.to raise_error(Saboteur::ConfigError, /expected a mapping/)
  end

  it "coerces numbers from strings and single values into lists" do
    config = described_class.new({ "timeout_factor" => "2.5", "include" => "lib/x.rb", "jobs" => "4" }, root: @root)
    expect([config["timeout_factor"], config["include"], config["jobs"]]).to eq([2.5, ["lib/x.rb"], 4])
  end

  it "accepts more than one job and rejects zero or negative limits, each with its own message" do
    expect(described_class.new({ "jobs" => 2 })["jobs"]).to eq(2)
    { "max_memory_mb" => 0, "max_processes" => 0, "timeout_factor" => 0, "timeout_min" => -1 }.each do |key, value|
      expect { described_class.new({ key => value }) }.to raise_error(Saboteur::ConfigError, /#{key} must be > 0/)
    end
  end

  # A fixed default makes every run repeatable; --seed or seed: changes it.
  it "seeds runs with 1 by default and rejects a negative seed" do
    expect(described_class.new({})["seed"]).to eq(1)
    expect(described_class.new({ "seed" => "7" })["seed"]).to eq(7)
    expect { described_class.new({ "seed" => -1 }) }.to raise_error(Saboteur::ConfigError, /seed must be >= 0/)
  end

  it "has no path for a setting that is off" do
    expect(described_class.new({ "json_report" => nil }, root: @root).path("json_report")).to be_nil
  end
end
