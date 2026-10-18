# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::BundleGemfilePin do
  describe ".pinned_in" do
    it "reads a leading BUNDLE_GEMFILE assignment" do
      expect(described_class.pinned_in("BUNDLE_GEMFILE=gemfiles/x.gemfile bundle exec rspec"))
        .to eq("gemfiles/x.gemfile")
    end

    it "reads a BUNDLE_GEMFILE assignment that follows other leading assignments (#722)" do
      expect(described_class.pinned_in("A=1 BUNDLE_GEMFILE=gemfiles/x.gemfile bundle exec rspec"))
        .to eq("gemfiles/x.gemfile")
      expect(described_class.pinned_in("A=1 B=two BUNDLE_GEMFILE=\"gem files/x.gemfile\" rspec"))
        .to eq("gem files/x.gemfile")
    end

    it "reads the LAST BUNDLE_GEMFILE assignment, like the shell (#722)" do
      expect(described_class.pinned_in("BUNDLE_GEMFILE=a BUNDLE_GEMFILE=b cmd")).to eq("b")
    end

    it "reads pins an env or timeout wrapper carries (#722)" do
      expect(described_class.pinned_in("env BUNDLE_GEMFILE=g cmd")).to eq("g")
      expect(described_class.pinned_in("env -i BUNDLE_GEMFILE=g cmd")).to eq("g")
      expect(described_class.pinned_in("/usr/bin/env A=1 BUNDLE_GEMFILE=g cmd")).to eq("g")
      expect(described_class.pinned_in("timeout 60 env BUNDLE_GEMFILE=g cmd")).to eq("g")
    end

    it "reads past an empty earlier assignment (#722)" do
      expect(described_class.pinned_in("A= BUNDLE_GEMFILE=g cmd")).to eq("g")
    end

    it "treats an empty BUNDLE_GEMFILE= as unset, like the shell (#722)" do
      expect(described_class.pinned_in("BUNDLE_GEMFILE= rspec")).to be_nil
      expect(described_class.pinned_in("BUNDLE_GEMFILE=g BUNDLE_GEMFILE= rspec")).to be_nil
    end

    it "treats A=\"x\"BUNDLE_GEMFILE=g as one assignment to A, setting nothing (#722)" do
      expect(described_class.pinned_in('A="x"BUNDLE_GEMFILE=g cmd')).to be_nil
    end

    it "refuses BUNDLE_GEMFILE it cannot read as a leading pin, failing closed (#722)" do
      [
        "bundle exec rspec BUNDLE_GEMFILE=g",
        "export BUNDLE_GEMFILE=g; bundle exec rspec",
        "cd sub && BUNDLE_GEMFILE=g rspec",
        'sh -c "BUNDLE_GEMFILE=g rspec"',
        "BUNDLE_GEMFILE=$(cat gemfile_name) rspec",
        "BUNDLE_GEMFILE=g;rspec",
        "BUNDLE_GEMFILE=g&rspec",
        "BUNDLE_GEMFILE=~/g rspec",
        "BUNDLE_GEMFILE=g* rspec",
        "BUNDLE_GEMFILE=g(x) rspec"
      ].each do |command|
        expect { described_class.pinned_in(command) }
          .to raise_error(Saboteur::ConfigError, /pin BUNDLE_GEMFILE as a leading assignment/), command
      end
    end

    it "refuses env flags that re-point cwd, re-parse words, or unset variables with a pin in play (#722)" do
      [
        "env -C sub BUNDLE_GEMFILE=g rspec",
        "env --chdir=sub BUNDLE_GEMFILE=g rspec",
        'env -S "BUNDLE_GEMFILE=g rspec"',
        'env --split-string "BUNDLE_GEMFILE=g rspec"',
        "env -u BUNDLE_GEMFILE rspec",
        "env --unset BUNDLE_GEMFILE rspec",
        "env --unset=BUNDLE_GEMFILE rspec",
        "BUNDLE_GEMFILE=g env -u BUNDLE_GEMFILE rspec",
        "env -i -u BUNDLE_GEMFILE BUNDLE_GEMFILE=g rspec"
      ].each do |command|
        expect { described_class.pinned_in(command) }
          .to raise_error(Saboteur::ConfigError, /pin BUNDLE_GEMFILE as a leading assignment/), command
      end
    end

    it "is nil when the command does not mention BUNDLE_GEMFILE" do
      expect(described_class.pinned_in("bundle exec rspec")).to be_nil
      expect(described_class.pinned_in("env -u FOO rspec")).to be_nil
      expect(described_class.pinned_in("env -C sub rspec")).to be_nil
    end
  end
end
