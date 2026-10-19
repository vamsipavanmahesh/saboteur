# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::RunValidation do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the run option validation, moved out of CLI itself" do
    owned = %i[reject_test_selection_conflicts reject_test_command_conflicts validate_run_options
               reject_format_conflicts]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end
end
