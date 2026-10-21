# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::FiddleLoader, "#require_fiddle! (#639)" do
  it "loads fiddle (and its import mixin) through the one guarded door" do
    expect { described_class.require_fiddle!(with_import: true) }.not_to raise_error
    expect(defined?(Fiddle::Pointer)).to eq("constant")
  end

  it "refuses with the fixes when fiddle cannot load, naming every working fix" do
    allow(described_class).to receive(:require).and_raise(LoadError)
    expect { described_class.require_fiddle! }.to raise_error(
      Saboteur::Error,
      a_string_including("default gem", "gem install fiddle", 'gem "fiddle"', "Gemfile",
                         "libffi-dev", "libffi-devel")
    )
  end

  it "refuses for fiddle/import too, not only for fiddle itself" do
    call = 0
    allow(described_class).to receive(:require) do |_name|
      call += 1
      raise LoadError if call == 2
    end
    expect { described_class.require_fiddle!(with_import: true) }.to raise_error(Saboteur::Error, /refuses to run/)
  end

  # The pin that matters: a sandbox layer must never turn the refusal into
  # a warn-and-continue (an unsandboxed run that only notes the fact).
  describe "sandbox layers fail closed on the refusal" do
    # Clear the memoized probes before AND after: a memo set by an earlier
    # example would short-circuit before the loader is ever asked, and the
    # real probe re-runs cheaply for whatever runs next.
    def clear_probe_memos
      [Saboteur::Execution::Sandbox, Saboteur::Execution::Seatbelt].each do |mod|
        %i[@abi_version @probe].each do |ivar|
          mod.send(:remove_instance_variable, ivar) if mod.instance_variable_defined?(ivar)
        end
      end
    end

    before do
      clear_probe_memos
      allow(described_class).to receive(:require_fiddle!).and_raise(Saboteur::Error, described_class::MESSAGE)
    end

    after { clear_probe_memos }

    it "Sandbox.abi_version propagates the refusal instead of degrading to unsandboxed" do
      allow(Saboteur::Execution::Sandbox).to receive(:linux?).and_return(true)
      expect { Saboteur::Execution::Sandbox.abi_version }.to raise_error(Saboteur::Error, /fiddle/)
    end

    it "Seatbelt.probe propagates the refusal instead of reporting :unavailable" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      expect { Saboteur::Execution::Seatbelt.probe }.to raise_error(Saboteur::Error, /fiddle/)
    end
  end

  # The grep gate: no file loads fiddle directly, top-level or inline, so a
  # future touchpoint cannot sneak the bundler-time failure back in (#639).
  it "keeps every fiddle load behind FiddleLoader.require_fiddle!" do
    lib = File.expand_path("../../../lib", __dir__)
    offenders = Dir[File.join(lib, "**", "*.rb")].reject { |file| file.end_with?("fiddle_loader.rb") }
                                                 .flat_map do |file|
      File.readlines(file, encoding: "UTF-8").each_with_index.filter_map do |line, index|
        "#{file}:#{index + 1}" if line.match?(/^\s*require "fiddle/)
      end
    end
    expect(offenders).to eq([])
  end
end
