# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The engine hands the reeval strategy and the whole_file list to the one
# Reevaluator that both the scheduler and the runner share.
RSpec.describe Saboteur::Engine, "whole_file wiring" do
  it "builds the shared reevaluator from the reeval and whole_file settings" do
    config = Saboteur::Config.new({ "reeval" => "class_eval", "whole_file" => ["Gate#open"] })
    reevaluator = instance_double(Saboteur::Execution::Reevaluator)
    allow(Saboteur::Execution::Reevaluator).to receive(:new).and_return(reevaluator)
    allow(Saboteur::Execution::Runner).to receive(:new)
    allow(Saboteur::Engine::Scheduler).to receive(:new)
    engine = described_class.new(config, err: StringIO.new)
    allow(engine).to receive_messages(hooks: nil, supervisor: nil, fresh_log_dir: "/tmp")

    engine.send(:scheduler_for, nil, nil, nil)

    expect(Saboteur::Execution::Reevaluator).to have_received(:new).with("class_eval", whole_file: ["Gate#open"])
    expect(Saboteur::Execution::Runner).to have_received(:new).with(hash_including(reevaluator: reevaluator))
    expect(Saboteur::Engine::Scheduler).to have_received(:new).with(hash_including(reevaluator: reevaluator))
  end
end
