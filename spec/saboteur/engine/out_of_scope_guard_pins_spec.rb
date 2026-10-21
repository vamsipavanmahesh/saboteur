# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::OutOfScopeGuard, "refuse_out_of_scope_changes pins" do
  let(:engine) { Saboteur::Engine.new(Saboteur::Config.new({}), err: StringIO.new) }

  def guess(changed:, out_of_scope:)
    double("guess", changed: changed, out_of_scope: out_of_scope, out_of_scope_message: "hidden by scope")
  end

  def refuse(guess)
    engine.send(:refuse_out_of_scope_changes, guess)
  end

  it "raises the scope message when every changed file is outside the scope" do
    expect { refuse(guess(changed: 0, out_of_scope: ["lib/x.rb"])) }
      .to raise_error(Saboteur::ConfigError, "hidden by scope")
  end

  it "does not raise while some changed file is inside the scope" do
    expect { refuse(guess(changed: 1, out_of_scope: ["lib/x.rb"])) }.not_to raise_error
  end

  it "does not raise when nothing fell outside the scope" do
    expect { refuse(guess(changed: 0, out_of_scope: [])) }.not_to raise_error
  end
end
