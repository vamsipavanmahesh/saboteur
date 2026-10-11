# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "config"

module Saboteur
  # The text printed by `saboteur --help` and `saboteur help <command>`.
  #
  # It is a map of everything saboteur can do, for people and for AI agents that
  # have no docs. The layout is fixed: section headers are upper case on their
  # own line, command and key rows start with two spaces. Option lines come from
  # the CLI's own option parser, so a new option shows up here without an edit.
  class Help
    Command = Data.define(:name, :summary, :description, :takes_options, :exit_codes, :examples)

    PURPOSE = "mutation testing for Ruby and RSpec"
    DOCUMENTATION = "https://github.com/vamsipavanmahesh/saboteur"

    EXIT_CODE_MEANINGS = {
      0 => "Success. Without --threshold: no unignored survivors, and at most half of the executed mutants " \
           "errored. With --threshold: the score is at or above it, even if mutants survived.",
      1 => "Without --threshold: at least one mutant survived and is not on the ignore list. With --threshold " \
           "(survivors alone no longer fail the run): the score is below it, or no mutant was tested so " \
           "there is no score.",
      2 => "Usage or configuration error: fix the command or .saboteur.yml. A replay --id that matches no " \
           "mutant is only found after the target has booted. A named source or test file that does not exist.",
      3 => "Tool error: saboteur could not finish, or more than half of the executed mutants errored (such " \
           "a run tested almost nothing). With --threshold, also any errored or resource-limited mutant."
    }.freeze

    DOCTOR_EXIT_CODE_MEANINGS = {
      0 => "Healthy: the environment checks passed and the baseline passed twice in the same order.",
      2 => "Usage or configuration error: fix the command or .saboteur.yml.",
      3 => "A check failed: the target did not boot, or the baseline failed or changed between runs."
    }.freeze

    COMMANDS = [
      Command.new(
        name: "run",
        summary: "Mutate your code and report the mutants your tests do not catch",
        description: "Builds a per-test coverage map, makes small changes to your methods, runs only the " \
                     "tests that cover each change, and reports survivors (changes no test noticed). Source files or " \
                     "directories after run replace include and exclude; --test limits the specs that run; " \
                     "--threshold PERCENT replaces the survivor check: exit 0 when the score is at or above " \
                     "PERCENT, exit 1 when it is below.",
        takes_options: true,
        exit_codes: EXIT_CODE_MEANINGS,
        examples: [
          ["Pull request: only methods changed since the target branch", "saboteur run --since origin/main"],
          ["Whole project, four workers, repeatable seed", "saboteur run --jobs 4 --seed 42"],
          ["One class or method", "saboteur run --subject 'Person#adult?'"],
          ["Replay one mutant by the digest printed next to a survivor", "saboteur run --id 1a2b3c4d5e6f7a8b"],
          ["Mutate named files against named specs, skipping the whole-suite coverage run",
           "saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb --test spec/b_spec.rb"],
          ["CI gate: exit 1 when the score is below 90 percent", "saboteur run --threshold 90"]
        ]
      ),
      Command.new(
        name: "doctor",
        summary: "Check the environment and run the baseline twice, without mutating anything",
        description: "Boots the target like a run, checks runtime, coverage and boot files, then runs your " \
                     "suite twice in the same order with one seed and reports whether both runs passed. " \
                     "It never mutates anything.",
        takes_options: true,
        exit_codes: DOCTOR_EXIT_CODE_MEANINGS,
        examples: [["Check the setup before the first run", "saboteur doctor"],
                   ["Use another config file and seed", "saboteur doctor --config ci.yml --seed 7"]]
      ),
      Command.new(
        name: "version",
        summary: "Print the installed version",
        description: "Prints the version number and nothing else.",
        takes_options: false,
        exit_codes: nil,
        examples: [["Print the version", "saboteur version"]]
      ),
      Command.new(
        name: "help",
        summary: "Show this map, or details for one command: saboteur help <command>",
        description: "Without an argument, prints every command, option, config key and exit code. " \
                     "With a command name, prints that command's usage, options and examples.",
        takes_options: false,
        exit_codes: nil,
        examples: [["Show everything", "saboteur help"], ["Show one command", "saboteur help run"]]
      )
    ].freeze

    FILES = [
      [".saboteur.yml", "Settings. Command line options override it."],
      [".saboteur-ignore.yml", "Accepted survivors: entries with subject, mutation (digest) and a required reason."],
      [".saboteur/report.json", "Stryker mutation-testing-report-schema JSON (--json changes the path)."],
      [".saboteur/report.html", "Self-contained HTML report (--html changes the path)."],
      [".saboteur/", "Cache: coverage map and incremental verdicts. Safe to delete."]
    ].freeze

    # option_lines: the option lines of each command's parser, keyed by command name.
    def initialize(option_lines:, commands: COMMANDS)
      @option_lines = option_lines
      @commands = commands
    end

    def overview
      [title, usage_section, commands_section, *option_sections, examples_section(all_examples),
       *exit_code_sections, config_section, files_section, "Documentation: #{DOCUMENTATION}\n"].join("\n")
    end

    # Details for one command, or nil when there is no such command.
    def command(name)
      found = @commands.find { |candidate| candidate.name == name }
      return unless found

      sections = ["saboteur #{found.name} - #{found.summary}\n", "#{found.description}\n", command_usage(found)]
      sections << options_section(found) if found.takes_options
      sections << examples_section(found.examples)
      sections << exit_codes_section(found.exit_codes) if found.exit_codes
      sections.join("\n")
    end

    def command_names
      @commands.map(&:name)
    end

    private

    # One section for every command that takes options, so the overview needs no other page.
    def option_sections
      @commands.select(&:takes_options).map { |command| options_section(command) }
    end

    def exit_code_sections
      @commands.select(&:exit_codes).map { |command| exit_codes_section(command.exit_codes, command.name) }
    end

    def title
      "saboteur #{VERSION} - #{PURPOSE}\n"
    end

    def usage_section
      "USAGE\n  saboteur <command> [options]\n  saboteur help [command]\n"
    end

    def command_usage(command)
      suffix = command.takes_options ? " [options]" : ""
      "USAGE\n  saboteur #{command.name}#{suffix}\n"
    end

    def commands_section
      rows = @commands.map { |command| "  #{command.name.ljust(name_width)}  #{command.summary}" }
      "COMMANDS\n#{rows.join("\n")}\n"
    end

    def name_width
      @commands.map { |command| command.name.length }.max
    end

    def options_section(command)
      "OPTIONS (saboteur #{command.name})\n#{@option_lines.fetch(command.name).map(&:rstrip).join("\n")}\n"
    end

    def all_examples
      @commands.flat_map(&:examples)
    end

    def examples_section(examples)
      "EXAMPLES\n#{examples.map { |note, line| "  # #{note}\n  #{line}" }.join("\n")}\n"
    end

    def exit_codes_section(codes, command_name = nil)
      rows = codes.map { |code, meaning| "  #{code}  #{meaning}" }
      title = command_name ? "EXIT CODES (saboteur #{command_name})" : "EXIT CODES"
      "#{title}\n#{rows.join("\n")}\n"
    end

    def config_section
      rows = Config::DEFAULTS.map { |key, value| "  #{key}: #{describe_default(value)}" }
      intro = "Every key with its default value, as YAML. Unknown keys are an error."
      "CONFIG FILE (.saboteur.yml)\n#{intro}\n#{rows.join("\n")}\n"
    end

    # Valid YAML (JSON flow style), so a copied line keeps the default's meaning.
    def describe_default(value)
      JSON.generate(value)
    end

    def files_section
      "FILES\n#{FILES.map { |path, meaning| "  #{path.ljust(files_width)}  #{meaning}" }.join("\n")}\n"
    end

    def files_width
      FILES.map { |path, _| path.length }.max
    end
  end
end
