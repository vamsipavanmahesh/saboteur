# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::RunOutput do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the report announcement and the stdout redirect, moved out of CLI itself" do
    owned = %i[announce_reports stdout_on_stderr]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end
end
