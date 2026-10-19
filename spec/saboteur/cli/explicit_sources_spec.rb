# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::ExplicitSources do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the source operand handling, moved out of CLI itself" do
    owned = %i[use_explicit_sources source_pattern glob_escape require_existing_test]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end

  describe "test operands" do
    def check(test)
      Saboteur::CLI.new([]).send(:require_existing_test, test)
    end

    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.touch(["a_spec.rb", "a:1b_spec.rb"])
          example.run
        end
      end
    end

    it "accepts a file with a line or example selector" do
      expect { check("a_spec.rb") }.not_to raise_error
      expect { check("a_spec.rb:12") }.not_to raise_error
      expect { check("a_spec.rb:12:34") }.not_to raise_error
      expect { check("a_spec.rb[1:2,1:3]") }.not_to raise_error
      expect { check("a_spec.rb[1:2][1:3]") }.not_to raise_error
    end

    it "strips a selector only at the end of the path" do
      expect { check("a:1b_spec.rb") }.not_to raise_error
    end

    it "does not take an empty selector for one" do
      expect { check("a_spec.rb:") }.to raise_error(Saboteur::CLI::UsageError, "test file not found: a_spec.rb:")
      expect { check("a_spec.rb[]") }.to raise_error(Saboteur::CLI::UsageError, "test file not found: a_spec.rb[]")
    end
  end
end
