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

  it "knows which keys were set explicitly, and carries that through a clone (#296)" do
    config = described_class.new({ "json_report" => "custom.json" }, root: @root)
    expect(config.explicit?("json_report")).to be(true)
    expect(config.explicit?("html_report")).to be(false)

    clone = described_class.new(config.to_h, root: config.root, explicit: config.explicit_keys)
    expect(clone.explicit?("json_report")).to be(true)
    expect(clone.explicit?("html_report")).to be(false)
  end

  it "drops explicitness for keys a clone replaces or removes (#296)" do
    config = described_class.new({ "json_report" => "custom.json", "subjects" => ["A#b"] }, root: @root)
    clone = config.with({ "tests" => ["spec/a_spec.rb"] }, except: ["json_report"])
    expect(clone.explicit?("json_report")).to be(false)
    expect(clone.explicit?("tests")).to be(true)
    expect(clone.explicit?("subjects")).to be(true)
  end

  it "tracks explicit keys given as symbols (#296)" do
    config = described_class.new({ "json_report" => "custom.json" }, root: @root, explicit: [:json_report])
    expect(config.explicit?("json_report")).to be(true)
  end

  it "drops explicitness for symbol except keys in a clone (#296)" do
    config = described_class.new({ "json_report" => "custom.json" }, root: @root)
    expect(config.with({}, except: [:json_report]).explicit?("json_report")).to be(false)
  end

  it "keeps the root it is loaded with" do
    expect(described_class.load(root: @root).root).to eq(@root)
  end

  it "hands out a copy of its values from to_h" do
    config = described_class.load(root: @root)
    config.to_h["jobs"] = 99
    expect(config.to_h["jobs"]).to eq(1)
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

  it "collects repeatable score gates as pattern/floor pairs (#473)" do
    write("app/payments/charge.rb", "class Charge; end\n")
    write("app/legacy/old.rb", "class Old; end\n")
    write("config/saboteur.rb", <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["app/**/*.rb"]
        c.score_gate "app/payments/**/*", min_score: 95
        c.score_gate "app/legacy/**/*", min_score: 60.5
      end
    RUBY
    expect(described_class.load(root: @root)["score_gates"]).to eq(
      [{ "pattern" => "app/payments/**/*", "min_score" => 95.0 },
       { "pattern" => "app/legacy/**/*", "min_score" => 60.5 }]
    )
  end

  it "rejects a score gate floor that is not a 0-100 number (#473)" do
    write("app/x.rb", "class X; end\n")
    write("config/saboteur.rb", 'Saboteur.configure { |c| c.score_gate "app/**/*", min_score: 101 }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, /min_score must be between 0 and 100/)

    write("config/saboteur.rb", 'Saboteur.configure { |c| c.score_gate "app/**/*", min_score: "high" }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, /min_score must be between 0 and 100/)
  end

  # NaN fails every comparison, including between?: an unguarded range
  # check leaks a bare ArgumentError instead of the config error.
  it "rejects a NaN score gate floor with the 0-100 message (#565)" do
    write("app/x.rb", "class X; end\n")
    write("config/saboteur.rb", 'Saboteur.configure { |c| c.score_gate "app/**/*", min_score: Float::NAN }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, /min_score must be between 0 and 100/)
  end

  it "validates score gates against the real path of a symlinked root (#473)" do
    write("app/payments/x.rb", "class X; end\n")
    write("config/saboteur.rb",
          'Saboteur.configure { |c| c.include = ["app/**/*.rb"]; c.score_gate "app/payments/**/*", min_score: 95 }')
    link = File.join(Dir.mktmpdir, "linked")
    File.symlink(@root, link)
    expect { described_class.load(root: link) }.not_to raise_error
  end

  it "rejects a score gate whose pattern matches no included file (#473)" do
    write("app/x.rb", "class X; end\n")
    write("config/saboteur.rb",
          'Saboteur.configure { |c| c.include = ["app/**/*.rb"]; c.score_gate "app/payments/**/*", min_score: 95 }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, %r{score_gate.*app/payments.*matches no included file})
  end

  it "normalizes string floors to floats on load (#473)" do
    write("app/payments/x.rb", "class X; end\n")
    write("config/saboteur.rb",
          'Saboteur.configure { |c| c.include = ["app/**/*.rb"]; c.score_gate "app/payments/**/*", min_score: "95" }')
    gates = described_class.load(root: @root)["score_gates"]
    expect(gates).to eq([{ "pattern" => "app/payments/**/*", "min_score" => 95.0 }])
    expect(gates.first["min_score"]).to be_a(Float)
  end

  it "accepts score gate floors on the 0 and 100 boundary, rejecting just outside (#473)" do
    write("app/x.rb", "class X; end\n")
    [0, 100].each do |floor|
      write("config/saboteur.rb",
            "Saboteur.configure { |c| c.include = [\"app/**/*.rb\"]; c.score_gate \"app/**/*\", min_score: #{floor} }")
      expect { described_class.load(root: @root) }.not_to raise_error
    end
    [100.5, -0.5].each do |floor|
      write("config/saboteur.rb",
            "Saboteur.configure { |c| c.score_gate \"app/**/*\", min_score: #{floor} }")
      expect { described_class.load(root: @root) }
        .to raise_error(Saboteur::ConfigError, /min_score must be between 0 and 100/)
    end
  end

  it "rejects an empty score gate pattern (#473)" do
    write("app/x.rb", "class X; end\n")
    write("config/saboteur.rb", 'Saboteur.configure { |c| c.score_gate "", min_score: 50 }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, /pattern must not be empty/)
  end

  it "names the offending floor in a score gate error, whether unparsable or out of range (#473)" do
    write("app/x.rb", "class X; end\n")
    { "101" => "got 101", '"high"' => 'got "high"', "nil" => "got nil", "-1" => "got -1" }.each do |floor, shown|
      write("config/saboteur.rb", "Saboteur.configure { |c| c.score_gate \"app/**/*\", min_score: #{floor} }")
      expect { described_class.load(root: @root) }
        .to raise_error(Saboteur::ConfigError, "score_gate min_score must be between 0 and 100, #{shown}")
    end
  end

  it "does not touch the file system when no score gate is set (#473)" do
    config = described_class.new({}, root: File.join(@root, "missing"))
    expect(config["score_gates"]).to eq([])
  end

  it "keeps guess_tests as a no-op alias and warns only on an explicit opt-out" do
    expect(described_class.new({}, root: @root)["guess_tests"]).to be(false)
    expect(described_class.new({}, root: @root).deprecation_warnings).to eq([])
    expect(described_class.new({ "guess_tests" => true }, root: @root)["guess_tests"]).to be(true)
    expect(described_class.new({ "guess_tests" => true }, root: @root).deprecation_warnings).to eq([])
    opt_out = described_class.new({ "guess_tests" => false }, root: @root)
    expect(opt_out.deprecation_warnings).to eq(
      ["guess_tests = false is deprecated: inferred specs are the default and it no longer restores the " \
       "whole suite; use --all or c.test_selection = :all to run every spec"]
    )
  end

  it "defaults to inferred test selection and validates test_selection" do
    expect(described_class.new({}, root: @root)["test_selection"]).to eq("auto")
    expect(described_class.new({}, root: @root)["all"]).to be(false)
    expect(described_class.new({ "test_selection" => :all }, root: @root)["test_selection"]).to eq("all")
    expect { described_class.new({ "test_selection" => "sometimes" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /test_selection must be one of: auto, all/)
  end

  it "rejects an operator selection that leaves no effective operator" do
    all = Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys
    expect { described_class.new({ "exclude_operators" => all }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /operator selection is empty/)
    expect(described_class.new({ "operators" => ["range"] }, root: @root)["operators"]).to eq(["range"])
  end

  it "keeps the underlying problem in the invalid-value error" do
    expect { described_class.new({ "jobs" => "many" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /\Ainvalid config value: .*many/)
  end

  it "turns every list entry into a string" do
    config = described_class.new({ "rspec_args" => [:fail_fast, 7] }, root: @root)
    expect(config["rspec_args"]).to eq(%w[fail_fast 7])
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

  # A dangling symlink matches Dir.glob but has no real path: it is not
  # mutation source, so it is skipped instead of crashing the run (#503).
  it "skips a dangling symlink in the include set instead of raising Errno::ENOENT" do
    write("lib/ok.rb", "")
    File.symlink("gone.rb", File.join(@root, "lib", "broken.rb"))
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect(config.included_files).to eq([File.join(@root, "lib", "ok.rb")])
  end

  it "skips a self-referencing symlink and one that runs through a regular file" do
    write("lib/ok.rb", "")
    File.symlink("loop.rb", File.join(@root, "lib", "loop.rb"))
    File.symlink("ok.rb/nope.rb", File.join(@root, "lib", "notdir.rb"))
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect(config.included_files).to eq([File.join(@root, "lib", "ok.rb")])
  end

  it "still raises when a regular file cannot be resolved" do
    write("lib/ok.rb", "")
    allow(File).to receive(:realpath).and_raise(Errno::EACCES)
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect { config.included_files }.to raise_error(Errno::EACCES)
  end

  it "keeps the exact bytes of a non-UTF-8 file name losslessly (#231)" do
    bytes = "caf\xE9.rb".b
    FileUtils.mkdir_p(File.join(@root, "lib"))
    # APFS rejects filenames that are not valid UTF-8 at creation time.
    begin
      File.binwrite(File.join(@root, "lib", bytes), "")
    rescue Errno::EILSEQ
      skip "this filesystem rejects filenames that are not valid UTF-8"
    end
    config = described_class.new({ "include" => ["lib/**/*.rb"], "exclude" => [] }, root: @root)
    expect(config.included_files.map(&:b)).to eq([File.join(@root, "lib", bytes).b])
  end

  it "names include and exclude patterns that match no file, so a stale path is never silent" do
    write("lib/a.rb", "")
    config = described_class.new({ "include" => ["lib/**/*.rb", "app/**/*.rb"],
                                   "exclude" => ["lib/a.rb", "lib/moved.rb"] }, root: @root)
    expect(config.unmatched_patterns).to eq(["include: app/**/*.rb", "exclude: lib/moved.rb"])
  end

  it "excludes spec and test files vendored under lib/ from the default scope (#504)" do
    write("lib/calc.rb", "")
    write("lib/capybara/spec/session/node_spec.rb", "")
    write("lib/capybara/spec/helper.rb", "")
    write("lib/foo/test/bar_test.rb", "")
    write("lib/foo/tests/baz.rb", "")
    write("lib/foo/test_helper.rb", "")
    config = described_class.new({}, root: @root)
    expect(config.included_files).to eq([File.join(@root, "lib", "calc.rb")])
  end

  it "treats a configured exclude as replacing the default vendored-spec shields (#504)" do
    write("lib/a.rb", "")
    write("lib/legacy/suite_spec.rb", "")
    config = described_class.new({ "exclude" => ["lib/a.rb"] }, root: @root)
    expect(config.included_files).to eq([File.join(@root, "lib", "legacy", "suite_spec.rb")])
  end

  it "does not warn about the default shields matching nothing, only about configured excludes" do
    write("lib/a.rb", "")
    config = described_class.new({}, root: @root)
    expect(config.unmatched_patterns).to eq([])
  end

  # The implicit-vs-explicit pair that pins the guard on its own (#567
  # dogfood survivors): an implicit default exclude that matches nothing
  # stays silent, while an explicit one is named.
  it "warns on an explicit exclude that matches nothing but not on the implicit defaults" do
    write("lib/a.rb", "")
    implicit = described_class.new({}, root: @root)
    expect(implicit.unmatched_patterns.grep(/^exclude:/)).to eq([])

    explicit = described_class.new({ "exclude" => ["lib/gone.rb"] }, root: @root)
    expect(explicit.unmatched_patterns).to eq(["exclude: lib/gone.rb"])

    # An explicit include with an implicit exclude: the include is still
    # checked - the guard must only silence the implicit exclude, never
    # the include side.
    mixed = described_class.new({ "include" => ["app/**/*.rb"] }, root: @root)
    expect(mixed.unmatched_patterns).to eq(["include: app/**/*.rb"])
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

  it "defaults coverage_parts to 1, coerces it, and rejects values below 1 (#741)" do
    expect(described_class.new({})["coverage_parts"]).to eq(1)
    expect(described_class.new({ "coverage_parts" => "4" })["coverage_parts"]).to eq(4)
    expect { described_class.new({ "coverage_parts" => 0 }) }
      .to raise_error(Saboteur::ConfigError, /coverage_parts must be >= 1/)
  end

  it "defaults baseline_passes to 2, accepts 1, and rejects values below 1 (#55)" do
    expect(described_class.new({})["baseline_passes"]).to eq(2)
    expect(described_class.new({ "baseline_passes" => 1 })["baseline_passes"]).to eq(1)
    expect(described_class.new({ "baseline_passes" => "3" })["baseline_passes"]).to eq(3)
    expect { described_class.new({ "baseline_passes" => 0 }) }.to raise_error(Saboteur::ConfigError,
                                                                              /baseline_passes must be >= 1/)
  end

  # --test-command replaces the in-process machinery, so conflicting
  # settings are rejected on the EFFECTIVE config, wherever they came
  # from (#305).
  it "rejects test_command combined with tests, incremental, or strict sandbox" do
    expect { described_class.new({ "test_command" => "make test", "tests" => ["spec/a_spec.rb"] }) }
      .to raise_error(Saboteur::ConfigError, /test_command cannot be combined with tests/)
    expect { described_class.new({ "test_command" => "make test", "incremental" => true }) }
      .to raise_error(Saboteur::ConfigError, /test_command cannot be combined with incremental/)
    expect { described_class.new({ "test_command" => "make test", "sandbox" => "strict" }) }
      .to raise_error(Saboteur::ConfigError, /sandbox "strict" cannot be honored/)
    expect(described_class.new({ "test_command" => "make test" })["test_command"]).to eq("make test")
  end

  it "rejects test_command combined with an active flaky_check, naming the missing scheduler (#476)" do
    %w[survivors decisive].each do |mode|
      expect { described_class.new({ "test_command" => "make test", "flaky_check" => mode }) }
        .to raise_error(Saboteur::ConfigError,
                        "test_command cannot be combined with flaky_check: an external run has no " \
                        "in-process scheduler to rerun the decisive tests through")
    end
  end

  # The allowed-mode guard pins both the rejection and the exact words: the
  # CLI rejects bad modes, and a direct or file-loaded Config must too (#476).
  it "rejects an unknown flaky_check mode with the allowed-modes message (#476)" do
    expect { described_class.new({ "flaky_check" => "sometimes" }) }
      .to raise_error(Saboteur::ConfigError, "flaky_check must be one of: off, survivors, decisive")

    write("config/saboteur.rb", 'Saboteur.configure { |c| c.flaky_check = "sometimes" }')
    expect { described_class.load(root: @root) }
      .to raise_error(Saboteur::ConfigError, "flaky_check must be one of: off, survivors, decisive")
  end

  it "accepts every documented flaky_check mode (#476)" do
    %w[off survivors decisive].each do |mode|
      expect(described_class.new({ "flaky_check" => mode })["flaky_check"]).to eq(mode)
    end
  end

  it "rejects a non-string test_command (#305 Architect)" do
    expect { described_class.new({ "test_command" => %w[make test] }) }
      .to raise_error(Saboteur::ConfigError, /test_command must be a string/)
    expect { described_class.new({ "test_command" => 42 }) }
      .to raise_error(Saboteur::ConfigError, /test_command must be a string/)
    expect { described_class.new({ "test_command" => false }) }
      .to raise_error(Saboteur::ConfigError, /test_command must be a string/)
  end

  it "rejects a blank test_command instead of treating it as unset (#305 QA)" do
    expect { described_class.new({ "test_command" => "" }) }
      .to raise_error(Saboteur::ConfigError, /test_command must not be blank/)
    expect { described_class.new({ "test_command" => "   " }) }
      .to raise_error(Saboteur::ConfigError, /test_command must not be blank/)
  end

  it "leaves max_duration unset by default and validates it when given (#245)" do
    expect(described_class.new({})["max_duration"]).to be_nil
    expect(described_class.new({})["max_duration_ok"]).to eq(false)
    expect(described_class.new({ "max_duration" => 600 })["max_duration"]).to eq(600.0)
    expect(described_class.new({ "max_duration" => "90" })["max_duration"]).to eq(90.0)
    expect { described_class.new({ "max_duration" => 0 }) }.to raise_error(Saboteur::ConfigError,
                                                                           /max_duration must be > 0/)
    expect { described_class.new({ "max_duration" => "soon" }) }.to raise_error(Saboteur::ConfigError)
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
  # The sidecar entries must be root-relative: the dirty-tree scan builds its
  # exclusion pathspecs from these strings (#638).
  it "returns the sidecar Gemfile and its lockfile relative to the root (#638)" do
    Dir.mktmpdir do |dir|
      config = described_class.new({}, root: File.realpath(dir))
      expect(config.ignored_tree_paths(gemfile: "gemfiles/Gemfile.saboteur"))
        .to eq([".saboteur", ".saboteur/report.json", ".saboteur/report.html",
                "gemfiles/Gemfile.saboteur", "gemfiles/Gemfile.saboteur.lock"])
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

  describe "coverage_recorder (#725)" do
    it "defaults to coverage, coerces a symbol and refuses anything else" do
      expect(described_class.new({})["coverage_recorder"]).to eq("coverage")
      expect(described_class.new({ "coverage_recorder" => :trace })["coverage_recorder"]).to eq("trace")
      expect { described_class.new({ "coverage_recorder" => "tracepoint" }) }
        .to raise_error(Saboteur::ConfigError, "coverage_recorder must be one of: coverage, trace")
    end
  end

  describe "partial_coverage (#46)" do
    it "is off by default and accepts shadow and use as a string or a symbol" do
      expect(described_class.new({})["partial_coverage"]).to eq("off")
      expect(described_class.new({ "partial_coverage" => :shadow })["partial_coverage"]).to eq("shadow")
      expect(described_class.new({ "partial_coverage" => :use })["partial_coverage"]).to eq("use")
    end

    it "rejects anything else, naming the choices" do
      expect { described_class.new({ "partial_coverage" => "on" }) }
        .to raise_error(Saboteur::ConfigError, "partial_coverage must be one of: off, shadow, use")
    end
  end
end

RSpec.describe Saboteur::Config, "resume (#471)" do
  it "is unset by default and an output path that is not a source change" do
    expect(described_class.new({})["resume"]).to be_nil
    expect(described_class.new({ "resume" => "state/run1" }).output_paths).to include("state/run1")
  end

  [[7, "an Integer"], ["", "an empty string"], ["  ", "a blank string"], [["a"], "an Array"]].each do |value, label|
    it "refuses #{label}" do
      expect { described_class.new({ "resume" => value }) }
        .to raise_error(Saboteur::ConfigError, "resume must be a non-blank directory path")
    end
  end

  {
    "matrix" => { "matrix" => true },
    "test_command" => { "test_command" => "bin/test" }
  }.each do |label, extra|
    it "refuses to combine with #{label}" do
      expect { described_class.new({ "resume" => "state" }.merge(extra)) }
        .to raise_error(Saboteur::ConfigError, /resume cannot be combined with matrix or test_command/)
    end
  end

  it "accepts a directory on its own" do
    expect(described_class.new({ "resume" => "state" })["resume"]).to eq("state")
  end
end

RSpec.describe Saboteur::Config, "OUTPUT_KEYS (#471)" do
  it "is the one list of output settings, each a real setting" do
    expect(described_class::OUTPUT_KEYS)
      .to eq(%w[cache_dir json_report html_report score_history resume])
    expect(described_class::OUTPUT_KEYS - described_class::DEFAULTS.keys).to be_empty
  end

  it "is the list the fingerprint, baseline evidence and output paths use" do
    expect(Saboteur::Engine::RunFingerprint::LOCATION_SETTINGS)
      .to eq(described_class::OUTPUT_KEYS + described_class::PRESENTATION_KEYS)
    expect(Saboteur::Baseline::RunEvidence::OUTPUT_SETTINGS)
      .to eq(described_class::OUTPUT_KEYS + described_class::PRESENTATION_KEYS)
    config = described_class.new({ "resume" => "state", "score_history" => "h.jsonl" }, root: Dir.pwd)
    expect(config.output_paths).to include("state", "h.jsonl", ".saboteur")
  end

  it "keeps presentation-only settings out of the paths but in the identity exclusions" do
    expect(described_class::PRESENTATION_KEYS).to eq(%w[palette])
    expect(described_class::PRESENTATION_KEYS - described_class::DEFAULTS.keys).to be_empty
    config = described_class.new({ "palette" => { "fail" => :magenta } }, root: Dir.pwd)
    expect(config.output_paths).not_to include("palette")
  end
end

RSpec.describe Saboteur::Config, "palette overrides" do
  before { @root = Dir.mktmpdir }
  after { FileUtils.remove_entry(@root) }

  it "accepts token overrides and rejects unknown tokens with the six valid keys" do
    expect(described_class.new({ "palette" => { "fail" => :magenta } }, root: @root)["palette"])
      .to eq("fail" => :magenta)
    expect { described_class.new({ "palette" => { "error" => :red } }, root: @root) }
      .to raise_error(Saboteur::ConfigError,
                      /unknown palette tokens: error \(valid: fail, pass, warn, info, dim, head\)/)
  end
end

RSpec.describe "files that read Config::OUTPUT_KEYS at load (#471)" do
  %w[saboteur/engine/run_fingerprint saboteur/baseline/run_evidence].each do |feature|
    it "loads #{feature} on its own" do
      lib = File.expand_path("../../lib", __dir__)
      output = IO.popen([RbConfig.ruby, "-I", lib, "-e", "require #{feature.inspect}; print :loaded",
                         { err: %i[child out] }], &:read)
      expect(output).to eq("loaded")
    end
  end
end
