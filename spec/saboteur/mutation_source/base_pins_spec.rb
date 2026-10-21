# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::Base, "pins" do
  it "names itself after its class" do
    expect(described_class.new.name).to eq("Saboteur::MutationSource::Base")
  end

  it "requires subclasses to implement mutations_for" do
    expect { described_class.new.mutations_for(double("subject")) }
      .to raise_error(NotImplementedError, "Saboteur::MutationSource::Base must implement #mutations_for")
  end

  it "names the subclass in the mutations_for error" do
    custom = stub_const("CustomSource", Class.new(described_class))
    expect { custom.new.mutations_for(double("subject")) }
      .to raise_error(NotImplementedError, "CustomSource must implement #mutations_for")
  end
end
