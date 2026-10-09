# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::Boot do
  describe ".refuse_recursion!" do
    it "refuses to start inside a saboteur child" do
      stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
      expect { described_class.refuse_recursion! }.to raise_error(Saboteur::Error, /refusing to start/)
    end

    it "lets a top-level run start" do
      stub_const("ENV", ENV.to_h.except(Saboteur::Execution::Supervisor::CHILD_ENV))
      expect { described_class.refuse_recursion! }.not_to raise_error
    end
  end

  # If the guard were missing, this spec must fail without starting a run:
  # everything after the guard raises a sentinel instead of doing work.
  it "is the first thing a run does" do
    stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
    allow(Saboteur::IgnoreList).to receive(:load).and_raise("guard missing: run went on")
    allow(described_class).to receive(:new).and_raise("guard missing: run went on")
    expect { Saboteur::Engine.new(Saboteur::Config.new({}, root: Dir.pwd)).call }
      .to raise_error(Saboteur::Error, /refusing to start/)
  end
end
