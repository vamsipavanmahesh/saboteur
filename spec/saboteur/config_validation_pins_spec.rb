# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Config, "validation pins" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def config(values = {}) = described_class.new(values, root: @root)

  describe "fail_fast" do
    it "is refused with more than one job, with the reason" do
      expect { config("fail_fast" => true, "jobs" => 2) }.to raise_error(
        Saboteur::ConfigError,
        "fail_fast needs jobs 1: parallel workers have already started the other subjects"
      )
    end

    it "is accepted with one job, and parallel jobs are accepted without it" do
      expect { config("fail_fast" => true, "jobs" => 1) }.not_to raise_error
      expect { config("fail_fast" => false, "jobs" => 4) }.not_to raise_error
    end
  end

  describe "sandbox" do
    it "accepts true, false, strict and seatbelt" do
      [true, false, "strict", "seatbelt"].each do |value|
        expect(config("sandbox" => value)["sandbox"]).to eq(value)
      end
    end

    it "refuses anything else and lists the choices" do
      expect { config("sandbox" => "yes") }
        .to raise_error(Saboteur::ConfigError, 'sandbox must be true, false, "strict", or "seatbelt"')
    end
  end

  describe "report paths" do
    it "refuses json and html reports at one path" do
      expect { config("json_report" => "r.out", "html_report" => "r.out") }.to raise_error(
        Saboteur::ConfigError,
        "json_report and html_report both point to #{File.join(@root, 'r.out')}; give each report its own path"
      )
    end

    it "refuses the score history sharing a path with either report" do
      message = "json_report, html_report and score_history must have distinct paths"

      expect { config("json_report" => "a", "html_report" => "b", "score_history" => "a") }
        .to raise_error(Saboteur::ConfigError, message)
      expect { config("json_report" => "a", "html_report" => "b", "score_history" => "b") }
        .to raise_error(Saboteur::ConfigError, message)
      expect { config("json_report" => "a", "html_report" => "b", "score_history" => "c") }.not_to raise_error
    end
  end

  describe "#with" do
    it "replaces values, drops excepted keys, and keeps the root and the explicit keys" do
      base = described_class.new({ "jobs" => 2, "threshold" => 50 }, root: @root, explicit: %w[jobs threshold])

      changed = base.with({ "seed" => 9 }, except: ["threshold"])

      expect(changed.root).to eq(@root)
      expect(changed["seed"]).to eq(9)
      expect(changed["jobs"]).to eq(2)
      expect(changed["threshold"]).to be_nil
      expect(changed.explicit_keys.map(&:to_s)).to contain_exactly("jobs", "seed")
    end
  end

  describe "#fetch" do
    it "returns the default for an unknown key and the value for a known one" do
      expect(config.fetch("no_such_key", 7)).to eq(7)
      expect(config.fetch("no_such_key")).to be_nil
      expect(config.fetch(:jobs, 7)).to eq(config["jobs"])
    end
  end

  describe "#operator_policy" do
    it "reports the selected and the excluded operators in that order" do
      policy = config("operators" => ["range"], "exclude_operators" => ["comparison"]).operator_policy

      expect(policy).to include("selected" => ["range"], "excluded" => ["comparison"])
    end
  end

  describe "arid" do
    it "names an invalid pattern with the regexp error" do
      error = begin
        Regexp.new("[")
      rescue RegexpError => e
        e.message
      end

      expect { config("arid" => ["["]) }.to raise_error(Saboteur::ConfigError, "invalid arid pattern: #{error}")
    end
  end

  describe ".load" do
    it "refuses the legacy YAML file and says where its settings go" do
      File.write(File.join(@root, described_class::LEGACY_FILE), "jobs: 2\n")

      expect { described_class.load(root: @root) }.to raise_error(
        Saboteur::ConfigError,
        "saboteur no longer reads #{described_class::LEGACY_FILE}; move its settings to " \
        "#{described_class::FILE} (see README)."
      )
    end
  end
end
