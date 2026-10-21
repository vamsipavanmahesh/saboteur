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
      expect do
        check("a_spec.rb:")
      end.to raise_error(Saboteur::CLI::UsageError,
                         "test file not found: a_spec.rb:; check the path or drop --test")
      expect do
        check("a_spec.rb[]")
      end.to raise_error(Saboteur::CLI::UsageError,
                         "test file not found: a_spec.rb[]; check the path or drop --test")
    end
  end

  # Behavior pins (#841): the dogfood run selects this spec by name, so the
  # operand methods are called here.
  describe "source operands" do
    let(:usage) { Saboteur::CLI::UsageError }

    def cli(*argv) = Saboteur::CLI.new(argv)

    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("lib/sub")
          FileUtils.touch(["lib/a.rb", "lib/sub/b.rb", "lib/notes.txt", "a_spec.rb", "lib/we[ir]d{1}*.rb"])
          example.run
        end
      end
    end

    describe "#source_pattern" do
      it "turns a directory into a recursive Ruby glob, with or without a trailing slash" do
        expect(cli.send(:source_pattern, "lib")).to eq("lib/**/*.rb")
        expect(cli.send(:source_pattern, "lib/")).to eq("lib/**/*.rb")
      end

      it "matches a named file only by itself" do
        expect(cli.send(:source_pattern, "lib/a.rb")).to eq("lib/a.rb")
        expect(cli.send(:source_pattern, "lib/we[ir]d{1}*.rb")).to eq("lib/we\\[ir\\]d\\{1\\}\\*.rb")
      end

      it "refuses a file that is not Ruby" do
        expect { cli.send(:source_pattern, "lib/notes.txt") }
          .to raise_error(usage, "source is not a Ruby file: lib/notes.txt")
      end

      it "refuses a path that does not exist" do
        expect { cli.send(:source_pattern, "lib/missing.rb") }
          .to raise_error(usage, "source file not found: lib/missing.rb")
        expect { cli.send(:source_pattern, "missing.txt") }
          .to raise_error(usage, "source file not found: missing.txt")
      end
    end

    describe "#glob_escape" do
      it "escapes every glob metacharacter and leaves other text alone" do
        expect(cli.send(:glob_escape, "a\\b*c?d[e]f{g}h-i/j.rb")).to eq("a\\\\b\\*c\\?d\\[e\\]f\\{g\\}h-i/j.rb")
      end
    end

    describe "#use_explicit_sources" do
      it "replaces include and exclude with the operands and remembers them" do
        run = cli("lib/a.rb", "lib")
        run.send(:options).merge!(exclude: ["x"])

        run.send(:use_explicit_sources)

        expect(run.send(:options)).to include(include: ["lib/a.rb", "lib/**/*.rb"], exclude: [])
        expect(run.instance_variable_get(:@sources)).to eq(["lib/a.rb", "lib"])
      end

      it "keeps its own copy of the operands when the argument list is emptied later" do
        run = cli("lib/a.rb")
        run.send(:use_explicit_sources)
        run.instance_variable_get(:@argv).clear
        expect(run.instance_variable_get(:@sources)).to eq(["lib/a.rb"])
      end

      it "leaves the configured scope alone when no operand is named" do
        run = cli
        run.send(:options).merge!(tests: ["a_spec.rb"])

        run.send(:use_explicit_sources)

        expect(run.send(:options)).to eq(tests: ["a_spec.rb"])
        expect(run.instance_variable_get(:@sources)).to be_nil
      end

      it "requires every --test file to exist, before looking at the operands" do
        run = cli("lib/a.rb")
        run.send(:options).merge!(tests: ["a_spec.rb", "gone_spec.rb:3"])

        expect do
          run.send(:use_explicit_sources)
        end.to raise_error(usage,
                           "test file not found: gone_spec.rb:3; check the path or drop --test")
        expect(run.send(:options)).not_to have_key(:include)
      end

      it "refuses a spec file given as a source operand" do
        expect { cli("lib/a.rb", "a_spec.rb").send(:use_explicit_sources) }
          .to raise_error(Saboteur::ConfigError, /spec files are not mutated.*a_spec\.rb/)
      end

      it "refuses an operand that does not exist" do
        expect { cli("lib/missing.rb").send(:use_explicit_sources) }
          .to raise_error(usage, "source file not found: lib/missing.rb")
      end
    end
  end
end
