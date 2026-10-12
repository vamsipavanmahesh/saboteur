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
      expect(error.message).to include("saboteur.rb:2", "'jobs'", "before the app boots")
    }
  end

  it "wraps a NoMethodError whose receiver is not the settings" do
    path = write_config("Saboteur.configure { |c| c.jobs = [].bogus }\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur.rb:1", "'bogus'", "before the app boots")
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
      expect(error.message).to include("saboteur.rb:1", "'bogus='", "before the app boots")
    }
  end

  it "returns the settings from Saboteur.configure" do
    path = write_config("raise 'no settings' unless Saboteur.configure { |c| c.jobs = 1 }.is_a?(Saboteur::ConfigFile::Settings)\n")
    expect { Saboteur::Config.load(root: @root, path: path) }.not_to raise_error
  end
end
