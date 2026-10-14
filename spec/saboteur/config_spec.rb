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

  it "keeps the root it is loaded with" do
    expect(described_class.load(root: @root).root).to eq(@root)
  end

  it "uses defaults without a config file" do
    config = described_class.load(root: @root)
    expect(config.to_h.values_at("integration", "timeout_factor", "timeout_min", "jobs", "reeval"))
      .to eq(["rspec", 3.0, 5.0, 1, "nesting"])
  end

  it "keeps whole_file as a list of subject id patterns, empty by default" do
    expect(described_class.new({})["whole_file"]).to eq([])
    expect(described_class.new({ "whole_file" => ["Gate#open", "Box*"] })["whole_file"]).to eq(["Gate#open", "Box*"])
  end

  it "has no threshold or explicit tests by default, and reads both from the file" do
    expect(described_class.load(root: @root).to_h.values_at("threshold", "tests")).to eq([nil, []])
    write("config/saboteur.rb", "Saboteur.configure { |c| c.threshold = 90; c.tests = [\"spec/a_spec.rb\"] }")
    config = described_class.load(root: @root)
    expect([config["threshold"], config["tests"]]).to eq([90.0, ["spec/a_spec.rb"]])
  end

  it "accepts the threshold bounds 0 and 100 and rejects values outside them" do
    expect(described_class.new({ "threshold" => 0 }, root: @root)["threshold"]).to eq(0.0)
    expect(described_class.new({ "threshold" => 100 }, root: @root)["threshold"]).to eq(100.0)
    [-0.1, 100.1].each do |value|
      expect { described_class.new({ "threshold" => value }, root: @root) }
        .to raise_error(Saboteur::ConfigError, /threshold must be between 0 and 100/)
    end
  end

  it "needs since for guess_tests and refuses it with tests" do
    expect(described_class.new({}, root: @root)["guess_tests"]).to be(false)
    expect(described_class.new({ "guess_tests" => true, "since" => "main" }, root: @root)["guess_tests"]).to be(true)
    expect { described_class.new({ "guess_tests" => true }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /guess_tests needs since/)
    expect do
      described_class.new({ "guess_tests" => true, "since" => "main", "tests" => ["spec/a_spec.rb"] }, root: @root)
    end
      .to raise_error(Saboteur::ConfigError, /guess_tests cannot be combined with tests/)
  end

  it "rejects an operator selection that leaves no effective operator" do
    all = Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys
    expect { described_class.new({ "exclude_operators" => all }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /operator selection is empty/)
    expect(described_class.new({ "operators" => ["range"] }, root: @root)["operators"]).to eq(["range"])
  end

  it "rejects a threshold that is not a number" do
    expect { described_class.new({ "threshold" => "high" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /invalid config value/)
  end

  it "reads config/saboteur.rb and lets CLI overrides win" do
    write("config/saboteur.rb", <<~RUBY)
      Saboteur.configure do |c|
        c.timeout_factor = 4
        c.jobs = 1
        c.reeval = "nesting"
      end
    RUBY
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

  it "resolves a symlinked include entry to its real path once" do
    write("lib/real.rb", "")
    File.symlink("real.rb", File.join(@root, "lib", "link.rb"))
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect(config.included_files).to eq([File.join(@root, "lib", "real.rb")])
  end

  it "keeps the exact bytes of a non-UTF-8 file name losslessly (#231)" do
    bytes = "caf\xE9.rb".b
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.binwrite(File.join(@root, "lib", bytes), "")
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect(config.included_files.map(&:b)).to eq([File.join(@root, "lib", bytes).b])
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

  it "defaults the per-method mutant limit to 100 and coerces configured integers" do
    expect(described_class.new["max_mutants_per_method"]).to eq(100)
    expect(described_class.new({ "max_mutants_per_method" => "7" })["max_mutants_per_method"]).to eq(7)
    [0, -1, "many"].each do |limit|
      expect { described_class.new({ "max_mutants_per_method" => limit }) }
        .to raise_error(Saboteur::ConfigError)
    end
  end

  it "reports YAML errors with the file name" do
    write(".saboteur.yml", "include: [\n")
    expect { described_class.load(root: @root) }.to raise_error(Saboteur::Error, /\.saboteur\.yml/)
  end

  it "expands paths relative to the root" do
    expect(described_class.new({},
                               root: @root).path("ignore_file")).to eq(File.join(@root, "config/saboteur_ignore.rb"))
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
    File.join(@root, path).tap { |full| FileUtils.mkdir_p(File.dirname(full)) && File.write(full, content) }
  end

  it "reads the config file it is given instead of config/saboteur.rb" do
    write("config/saboteur.rb", "Saboteur.configure { |c| c.jobs = 2 }")
    custom = write("custom.rb", "Saboteur.configure { |c| c.jobs = 3 }")
    expect(described_class.load(root: @root, path: custom)["jobs"]).to eq(3)
  end

  it "refuses a legacy .saboteur.yml with a pointer to the Ruby file" do
    write(".saboteur.yml", "jobs: 2\n")
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, %r{no longer reads \.saboteur\.yml.*config/saboteur\.rb})
  end

  it "refuses a legacy .saboteur-ignore.yml with a pointer to the Ruby file" do
    File.write(File.join(@root, ".saboteur-ignore.yml"), "- {subject: X#y, mutation: abc, reason: r}\n")
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError,
                      "saboteur no longer reads .saboteur-ignore.yml; " \
                      "move its entries to config/saboteur_ignore.rb (see README).")
  end

  it "treats an empty config file as defaults and reports a syntax error with the path" do
    write("config/saboteur.rb", "")
    expect(described_class.load(root: @root)["jobs"]).to eq(1)
    write("config/saboteur.rb", "Saboteur.configure { |c| c.jobs =")
    expect { described_class.load(root: @root) }.to raise_error(Saboteur::ConfigError, /saboteur\.rb.*:/)
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

  it "leaves the count gates off by default and rejects a malformed limit" do
    expect(described_class.new({}).to_h.values_at("max_timeouts", "max_errors")).to eq([nil, nil])
    expect(described_class.new({ "max_errors" => "5%" })["max_errors"]).to eq("5%")
    expect { described_class.new({ "max_timeouts" => "many" }) }
      .to raise_error(Saboteur::ConfigError, /max_timeouts must be a count/)
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

  it "rejects one path for both reports" do
    expect { described_class.new({ "json_report" => "out/r", "html_report" => "out/r" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, %r{json_report and html_report both point to .*out/r})
  end

  it "rejects the default JSON path used as the HTML path" do
    expect { described_class.new({ "html_report" => ".saboteur/report.json" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /give each report its own path/)
  end

  it "allows both reports to be off, or one of them" do
    expect { described_class.new({ "json_report" => nil, "html_report" => nil }, root: @root) }.not_to raise_error
    expect { described_class.new({ "html_report" => nil }, root: @root) }.not_to raise_error
  end
end

RSpec.describe Saboteur::Config, "#output_paths" do
  it "lists saboteur's own outputs inside the root, relative to it, and drops those outside" do
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      config = described_class.new({ "cache_dir" => ".saboteur", "json_report" => "out/r.json",
                                     "html_report" => "/elsewhere/r.html" }, root: root)
      expect(config.output_paths).to eq([".saboteur", "out/r.json"])
    end
  end
end

RSpec.describe Saboteur::Config, "matrix" do
  it "is off by default and refuses to combine with incremental reuse" do
    expect(described_class.new({})["matrix"]).to be(false)
    expect(described_class.new({ "matrix" => true })["matrix"]).to be(true)
    expect { described_class.new({ "matrix" => true, "incremental" => true }) }
      .to raise_error(Saboteur::ConfigError, /matrix cannot be combined with incremental/)
  end
end
