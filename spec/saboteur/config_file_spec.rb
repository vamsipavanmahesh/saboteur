# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::ConfigFile do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write_config(body)
    path = File.join(@root, "config", "saboteur.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  it "collects assignments into config values" do
    path = write_config(<<~RUBY)
      Saboteur.configure do |c|
        c.include = ["app/**/*.rb"]
        c.jobs = 4
        c.threshold = 80.0
      end
    RUBY
    config = Saboteur::Config.load(root: @root, path: path)
    expect([config["include"], config["jobs"], config["threshold"]]).to eq([["app/**/*.rb"], 4, 80.0])
  end

  it "says an unreadable config file is unreadable, not missing" do
    path = write_config("Saboteur.configure { |c| c.jobs = 4 }\n")
    allow(File).to receive(:readable?).and_call_original
    allow(File).to receive(:readable?).with(path).and_return(false)
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, "#{path}:cannot read the file - check its permissions")
  end

  it "rejects a Symbol integration with the config file and assignment line (#614)" do
    path = write_config("Saboteur.configure do |c|\n  c.integration = :rspec\nend\n")
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, "#{path}:2: integration must be a String, got :rspec; use \"rspec\"")
  end

  %w[run doctor].each do |command|
    it "reports invalid integration as exit 2 before #{command} boots (#614)" do
      path = write_config("Saboteur.configure { |c| c.integration = :rspec }")
      err = StringIO.new
      expect(Saboteur::Engine::Boot).not_to receive(:new)
      code = Dir.chdir(@root) do
        Saboteur::CLI.new([command, "--config", path], out: StringIO.new, err: err).call
      end
      expect(code).to eq(2)
      expect(err.string).to include("#{path}:1: integration must be a String, got :rspec")
      expect(err.string).not_to include("internal error")
    end
  end

  it "records a valid integration assignment (#614)" do
    settings = described_class::Settings.new
    settings.integration = "custom"
    expect(settings.values).to eq("integration" => "custom")
  end

  it "keeps a String integration usable by the run fingerprint (#614)" do
    path = write_config('Saboteur.configure { |c| c.integration = "rspec" }')
    config = Saboteur::Config.load(root: @root, path: path)
    expect(config["integration"]).to eq("rspec")
    expect { Saboteur::Engine::RunFingerprint.new(config: config).snapshot }.not_to raise_error
  end

  it "lets a later configure block win" do
    path = write_config(<<~RUBY)
      Saboteur.configure { |c| c.jobs = 2 }
      Saboteur.configure { |c| c.jobs = 6 }
    RUBY
    expect(Saboteur::Config.load(root: @root, path: path)["jobs"]).to eq(6)
  end

  it "supports ENV in the file, since it loads before the app boots" do
    path = write_config('Saboteur.configure { |c| c.since = ENV["SABOTEUR_SPEC_FLAG"] ? "origin/main" : nil }')
    ENV.delete("SABOTEUR_SPEC_FLAG")
    expect(Saboteur::Config.load(root: @root, path: path)["since"]).to be_nil
    ENV["SABOTEUR_SPEC_FLAG"] = "1"
    expect(Saboteur::Config.load(root: @root, path: path)["since"]).to eq("origin/main")
  ensure
    ENV.delete("SABOTEUR_SPEC_FLAG")
  end

  it "names the file, line and suggestion for an unknown setting" do
    path = write_config(<<~RUBY)
      Saboteur.configure do |c|
        c.jobs = 4
        c.timout_factor = 2
      end
    RUBY
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:3", 'unknown setting "timout_factor"',
                                       'did you mean "timeout_factor"')
    }
  end

  it "names the file and line for a wrong Integer value" do
    path = write_config("Saboteur.configure { |c| c.jobs = \"four\" }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, /saboteur\.rb:1: jobs must be an Integer, got "four"/)
  end

  it "names the file, line and key for a wrong Float value" do
    path = write_config("Saboteur.configure { |c| c.timeout_factor = \"high\" }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, /saboteur\.rb:1: timeout_factor must be a number, got "high"/)
  end

  it "names the file, line and key for a wrong nilable Float value" do
    path = write_config("Saboteur.configure { |c| c.threshold = \"high\" }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, /saboteur\.rb:1: threshold must be a number or nil, got "high"/)
  end

  it "accepts an Integer for a Float key and nil for a nilable Float key" do
    path = write_config("Saboteur.configure { |c| c.timeout_factor = 2; c.threshold = nil }\n")
    config = Saboteur::Config.load(root: @root, path: path)
    expect(config["timeout_factor"]).to eq(2.0)
    expect(config["threshold"]).to be_nil
  end

  it "hints at the load order when the file references an app constant" do
    path = write_config("Saboteur.configure { |c| c.include = MyApp::PATHS }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:1", "before the app boots")
    }
  end

  it "pins the full unknown-setting message" do
    path = write_config(<<~RUBY)
      Saboteur.configure do |c|
        c.timout_factor = 2
      end
    RUBY
    expected = "#{path}:2: unknown setting \"timout_factor\" (did you mean \"timeout_factor\"?). " \
               "Valid settings: #{Saboteur::Config::DEFAULTS.keys.join(', ')}"
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to eq(expected)
    }
  end

  it "omits the suggestion when nothing is close" do
    path = write_config(<<~RUBY)
      Saboteur.configure do |c|
        c.zzzzzz = 2
      end
    RUBY
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include('unknown setting "zzzzzz". Valid settings:')
      expect(error.message).not_to include("did you mean")
    }
  end

  it "wraps a NoMethodError that is not a setting assignment" do
    path = write_config(<<~RUBY)
      Saboteur.configure do |c|
        c.jobs
      end
    RUBY
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:2", "before the app boots")
      expect(error.message).to match(/[`']jobs'/)
    }
  end

  it "wraps a NoMethodError whose receiver is not the settings" do
    path = write_config("Saboteur.configure { |c| c.jobs = [].bogus }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:1", "before the app boots")
      expect(error.message).to match(/[`']bogus'/)
    }
  end

  it "wraps a bare unknown constant or call with the load-order hint" do
    path = write_config("bogus_call\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:1", "bogus_call", "before the app boots")
    }
  end

  it "refuses Saboteur.configure while no config file loads" do
    expect { Saboteur.configure { |c| c.jobs = 1 } }
      .to raise_error(RuntimeError, "Saboteur.configure is only valid while config/saboteur.rb loads")
  end

  it "pins the NameError message with the line number" do
    path = write_config("Saboteur.configure do |c|\n  c.include = [\"app/**/*.rb\"]\n  c.jobs = WORKERS\nend\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to start_with("#{path}:3: ")
      expect(error.message).to end_with("- this file loads before the app boots; use plain Ruby or ENV")
    }
  end

  it "rejects a setting value outside its range with the config's own message" do
    path = write_config("Saboteur.configure { |c| c.threshold = 101 }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }
      .to raise_error(Saboteur::ConfigError, /threshold must be between 0 and 100/)
  end

  it "wraps a NoMethodError from an assignment on a non-settings receiver" do
    path = write_config("[].bogus = 1\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:1", "before the app boots")
      expect(error.message).to match(/[`']bogus='/)
    }
  end

  it "returns the settings from Saboteur.configure" do
    path = write_config("raise 'no settings' unless Saboteur.configure { |c| c.jobs = 1 }.is_a?(Saboteur::ConfigFile::Settings)\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.not_to raise_error
  end

  it "records the gates set by repeatable c.score_gate calls (#473)" do
    settings = described_class::Settings.new
    settings.score_gate("app/**/*", min_score: 90)
    settings.score_gate("lib/**/*", min_score: 80)
    expect(settings.values["score_gates"].map { |gate| gate["pattern"] }).to eq(%w[app/**/* lib/**/*])
  end

  it "drops its collected settings after a load, whether the file loads or raises" do
    described_class.load(write_config("Saboteur.configure { |c| c.jobs = 2 }\n"))
    expect(described_class.instance_variable_get(:@settings)).to be_nil
    expect { described_class.load(write_config("Saboteur.configure { |c| c.jobs = 2 }\nraise 'boom'\n")) }
      .to raise_error(RuntimeError, "boom")
    expect(described_class.instance_variable_get(:@settings)).to be_nil
  end

  describe "message details" do
    def load_error(body)
      described_class.load(write_config(body))
    rescue Saboteur::ConfigError => e
      e.message
    end

    it "keeps only the first line of a LoadError message, after the path and a colon" do
      path = write_config("raise LoadError, \"first part\\nsecond part\"\n")
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError, "#{path}: first part")
    end

    it "keeps an empty LoadError message empty" do
      path = write_config("raise LoadError, \"\"\n")
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError, "#{path}: ")
    end

    it "suggests the closest key first when several are close" do
      message = load_error("Saboteur.configure { |c| c.max_duration_ox = 1 }\n")
      expect(message).to include("(did you mean \"max_duration_ok\"?)")
    end

    it "reports the config file line of an unknown setting set from another file" do
      stub_const("SPEC_SETTER", ->(settings) { settings.bogus_setting = 1 })
      path = write_config("Saboteur.configure do |c|\n  SPEC_SETTER.call(c)\nend\n")
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError, /\A#{Regexp.escape(path)}:2: unknown/)
    end

    it "reports the config file line of a NameError raised from another file" do
      stub_const("SPEC_RAISER", -> { raise NameError, "first\nsecond" })
      path = write_config("x = 1\nSPEC_RAISER.call\n")
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError, "#{path}:2: first - this file loads before the app boots; use plain Ruby or ENV"
      )
    end

    it "keeps an empty NameError message empty in the load-order hint" do
      stub_const("SPEC_RAISER", -> { raise NameError, "" })
      path = write_config("SPEC_RAISER.call\n")
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError, "#{path}:1:  - this file loads before the app boots; use plain Ruby or ENV"
      )
    end

    it "reports the config file line of a NoMethodError raised from another file" do
      stub_const("SPEC_RAISER", -> { nil.no_such_method_here })
      path = write_config("\nSPEC_RAISER.call\n")
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError, /\A#{Regexp.escape(path)}:2: /)
    end
  end
end
