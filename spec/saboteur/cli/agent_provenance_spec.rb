# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::AgentProvenance do
  it "is mixed into Saboteur::CLI like the other extracted pieces (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the agent provenance builder and settings, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(
      :agent_provenance, :agent_settings, :typed_settings, :agent_mode
    )
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(
      :agent_provenance, :agent_settings, :typed_settings, :agent_mode
    )
  end
end
