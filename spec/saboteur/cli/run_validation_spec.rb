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

  # Behavior pins (#841): dogfood selects these specs by file name, so the
  # methods must be called here, not only listed.
  describe "usage errors" do
    let(:cli) { Saboteur::CLI.new([]) }
    let(:usage) { Saboteur::CLI::UsageError }

    def with_options(**opts) = cli.send(:options).merge!(opts)

    describe "#reject_test_selection_conflicts" do
      it "accepts a run with no conflicting options" do
        with_options(tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_selection_conflicts) }.not_to raise_error
      end

      it "rejects --all with --test" do
        with_options(all: true, tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_selection_conflicts) }
          .to raise_error(usage, "--all cannot be combined with --test")
      end

      it "allows --all alone and --test with an empty list" do
        with_options(all: true, tests: [])

        expect { cli.send(:reject_test_selection_conflicts) }.not_to raise_error
      end

      it "rejects --all with --guess-tests" do
        with_options(all: true, guess_tests: true)

        expect { cli.send(:reject_test_selection_conflicts) }
          .to raise_error(usage, "--all cannot be combined with --guess-tests")
      end

      it "rejects --guess-tests with --test" do
        with_options(guess_tests: true, tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_selection_conflicts) }
          .to raise_error(usage, "--guess-tests cannot be combined with --test")
      end

      it "allows --guess-tests alone" do
        with_options(guess_tests: true)

        expect { cli.send(:reject_test_selection_conflicts) }.not_to raise_error
      end

      it "checks the --test-command conflicts too" do
        with_options(test_command: "true", tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_selection_conflicts) }
          .to raise_error(usage, "--test-command cannot be combined with --test")
      end
    end

    describe "#reject_test_command_conflicts" do
      it "accepts --test-command alone and no --test-command at all" do
        expect { cli.send(:reject_test_command_conflicts) }.not_to raise_error
        with_options(test_command: "true")
        expect { cli.send(:reject_test_command_conflicts) }.not_to raise_error
      end

      it "rejects --test-command with --test" do
        with_options(test_command: "true", tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_command_conflicts) }
          .to raise_error(usage, "--test-command cannot be combined with --test")
      end

      it "rejects --test-command with --incremental" do
        with_options(test_command: "true", incremental: true)

        expect { cli.send(:reject_test_command_conflicts) }
          .to raise_error(usage, "--test-command cannot be combined with --incremental")
      end

      it "ignores --incremental without --test-command" do
        with_options(incremental: true, tests: ["spec/a_spec.rb"])

        expect { cli.send(:reject_test_command_conflicts) }.not_to raise_error
      end
    end

    describe "#reject_format_conflicts" do
      def agent_cli(config:, gates: instance_double(Saboteur::Gates, any?: false))
        Saboteur::CLI.new(["--agent"]).tap do |agent|
          allow(agent).to receive_messages(config: config, gates: gates)
        end
      end

      it "names --threshold when agent mode has one" do
        expect { agent_cli(config: { "threshold" => 90 }).send(:reject_format_conflicts) }
          .to raise_error(usage, "--threshold cannot be combined with --agent")
      end

      it "names the gate option when agent mode has a score or limit gate" do
        gates = instance_double(Saboteur::Gates, any?: true, agent_option_name: "--max-* gates")

        expect { agent_cli(config: {}, gates: gates).send(:reject_format_conflicts) }
          .to raise_error(usage, "--max-* gates cannot be combined with --agent")
      end

      it "does not apply the agent gate rule outside agent mode" do
        gates = instance_double(Saboteur::Gates, any?: true)
        plain = Saboteur::CLI.new([])
        allow(plain).to receive_messages(config: { "threshold" => 90 }, gates: gates)

        expect { plain.send(:reject_format_conflicts) }.not_to raise_error
      end

      it "accepts agent mode with no gate" do
        expect { agent_cli(config: {}).send(:reject_format_conflicts) }.not_to raise_error
      end

      it "rejects --format json outside --dry-run" do
        cli.instance_variable_set(:@format, "json")

        expect { cli.send(:reject_format_conflicts) }.to raise_error(usage, /--format json is the --dry-run/)
      end

      it "allows --format json with --dry-run and other formats without it" do
        cli.instance_variable_set(:@format, "json")
        with_options(dry_run: true)
        expect { cli.send(:reject_format_conflicts) }.not_to raise_error

        other = Saboteur::CLI.new([])
        other.instance_variable_set(:@format, "text")
        expect { other.send(:reject_format_conflicts) }.not_to raise_error
      end
    end

    describe "#validate_run_options" do
      before do
        allow(cli).to receive_messages(reject_format_conflicts: nil, validate_shard_options: nil)
        allow(Saboteur::Selection::GitDiff).to receive(:verify_ref!)
      end

      it "runs the format and shard checks and skips the ref check without --since" do
        allow(cli).to receive(:config).and_return({ "since" => nil })

        cli.send(:validate_run_options)

        expect(cli).to have_received(:reject_format_conflicts)
        expect(cli).to have_received(:validate_shard_options)
        expect(Saboteur::Selection::GitDiff).not_to have_received(:verify_ref!)
      end

      it "verifies the --since ref against the config root" do
        allow(cli).to receive(:config).and_return(instance_double(Saboteur::Config, root: "/proj")
          .tap do |config|
            allow(config).to receive(:[]) do |key|
              { "since" => "main", "ignore_empty" => false }.fetch(key)
            end
          end)

        cli.send(:validate_run_options)

        expect(Saboteur::Selection::GitDiff).to have_received(:verify_ref!).with("main", root: "/proj")
      end

      it "refuses --ignore-empty without --since" do
        allow(cli).to receive(:config).and_return({ "since" => nil, "ignore_empty" => true })

        expect { cli.send(:validate_run_options) }.to raise_error(Saboteur::CLI::UsageError,
                                                                  /--ignore-empty applies to --since runs/)
      end
    end
  end
end
