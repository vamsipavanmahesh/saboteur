# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::DirtyTreeNotice do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the dirty tree warning, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(:warn_dirty_tree)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(:warn_dirty_tree)
  end
end
