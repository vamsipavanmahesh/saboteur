# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
           "there is no score. Also more timeout or errored mutants than --max-timeouts or --max-errors allow.",
      2 => "Usage or configuration error: fix the command or config/saboteur.rb. A replay --id that matches no " \
           "mutant is only found after the target has booted. A named source or test file that does not exist.",
      3 => "Tool error: saboteur could not finish, or more than half of the executed mutants errored (such " \
           "a run tested almost nothing), or a --since run skipped every subject of the change (for example " \
           "refinements or no coverage), so the change is unverified. With --threshold, also any errored or " \
           "resource-limited mutant.",
      4 => "Time budget spent: --max-duration stopped the run before the next subject, so the score is " \
           "partial. --max-duration-ok leaves the exit to the plain verdict: 0, 1, or 3 when the budget " \
           "stopped the run before any mutant was tested.",
      5 => "Baseline suite red: the unchanged suite failed its check, so no mutant ran. Fix your tests first.",
      70 => "Internal crash: a saboteur bug, never your code. The error line names a log with the full " \
            "backtrace; please report it."
    }.freeze

    DOCTOR_EXIT_CODE_MEANINGS = {
      0 => "Healthy: the environment checks passed and the baseline passed twice in the same order.",
      2 => "Usage or configuration error: fix the command or config/saboteur.rb.",
      3 => "A check failed: the target did not boot, or the baseline failed or changed between runs."
    }.freeze

    COMMANDS = [
      Command.new(
        name: "run",
        summary: "Mutate your code and report the mutants your tests do not catch",
        description: "Builds a per-test coverage map, makes small changes to your methods, runs only the " \
                     "tests that cover each change, and reports survivors (changes no test noticed). Source files or " \
                     "directories after run replace include and exclude. Without --test, the run infers the " \
                     "specs named after the mutated files and runs only those (with --since, plus every " \
                     "spec file the diff adds or changes that the suite loads); a mutated file with no " \
                     "conventional spec stops the run with exit 2 before anything boots, and --all keeps " \
                     "the whole configured suite. --threshold PERCENT replaces the survivor check: exit 0 " \
                     "when the score is at or above PERCENT, exit 1 when it is below. All operators run " \
                     "unless you select a smaller set; exclusions always remove operators from that set. " \
                     "Inline comment syntax: " \
                     '# saboteur:disable-line [operator ...] reason="...". A reason is required.',
        takes_options: true,
        exit_codes: EXIT_CODE_MEANINGS,
        examples: [
          ["Pull request: only methods changed since the target branch, with the inferred specs",
           "saboteur run --since origin/main"],
          ["Whole project and whole suite, four workers, repeatable seed", "saboteur run --all --jobs 4 --seed 42"],
          ["One deterministic CI shard of four", "saboteur run --all --shard 1/4"],
          ["One class or method", "saboteur run --subject 'Person#adult?'"],
          ["Replay one mutant by the digest printed next to a survivor", "saboteur run --id 1a2b3c4d5e6f7a8b"],
          ["Mutate named files against named specs, skipping the whole-suite coverage run",
           "saboteur run lib/a.rb lib/b.rb --test spec/a_spec.rb --test spec/b_spec.rb"],
          ["CI gate: exit 1 when the score is below 90 percent", "saboteur run --threshold 90"],
          ["AI agent: bounded JSON summary and strict exit codes", "saboteur run --agent --since origin/main"]
        ]
      ),
      Command.new(
        name: "pr",
        summary: "Preset: the fast pull-request loop over the lines changed since a ref",
        description: "Expands to saboteur run --baseline-passes 1 --max-duration 10m " \
                     "--since REF, with REF the first operand (default main): one baseline check, a " \
                     "ten-minute wall-clock budget, and mutants limited to the changed methods. The " \
                     "preset fails with exit 4 when the budget is spent; the summary counts the " \
                     "unrun mutants. Add --max-duration-ok to accept a partial verdict; other " \
                     "gates still apply. Every run option still works; explicit flags win (#654).",
        takes_options: true,
        exit_codes: EXIT_CODE_MEANINGS,
        examples: [["Changed lines since main", "saboteur pr"],
                   ["Changed lines since another target", "saboteur pr origin/develop"],
                   ["The same loop with two baseline checks", "saboteur pr --baseline-passes 2"]]
      ),
      Command.new(
        name: "audit",
        summary: "Preset: the whole project, all operators, both reports",
        description: "Expands to saboteur run --all --operators all --baseline-passes 2 " \
                     "--json .saboteur/audit-report.json --html .saboteur/audit-report.html: every " \
                     "subject against the whole suite, all operators, both baseline checks, writing " \
                     "the Stryker JSON and HTML reports. Configured selection limits (since, " \
                     "subjects, exclude_operators, max_duration) still apply; an explicit flag after " \
                     "the preset wins (#244), and an explicit --test replaces the injected --all.",
        takes_options: true,
        exit_codes: EXIT_CODE_MEANINGS,
        examples: [["Full project audit with JSON and HTML reports", "saboteur audit"]]
      ),
      Command.new(
        name: "doctor",
        summary: "Check the environment, and with --suite run the baseline twice, without mutating anything",
        description: "Boots the target like a run and checks runtime, coverage and boot files. With --suite " \
                     "it also runs your suite twice in the same order with one seed and reports whether both " \
                     "runs passed; --test PATH limits those runs to some specs. It never mutates anything. " \
                     "It certifies no versions of Rails, databases or tools saboteur never invokes (#318).",
        takes_options: true,
        exit_codes: DOCTOR_EXIT_CODE_MEANINGS,
        examples: [["Check the setup before the first run", "saboteur doctor"],
                   ["Also run the unchanged suite twice", "saboteur doctor --suite --seed 7"],
                   ["Run only some specs twice", "saboteur doctor --test spec/models"]]
      ),
      Command.new(
        name: "baseline",
        summary: "Check, propose or accept a fresh opt-in survivor baseline",
        description: "Check runs every mutant fresh and reports new, changed or unmatched accepted survivors. " \
                     "Propose writes a proposal with private local execution evidence. Edit only survivor reasons; " \
                     "accept verifies current inputs and publishes it. No scores or execution are suppressed. " \
                     "With --epsilon POINTS, check also fails when the score drops more than POINTS percentage " \
                     "points below the accepted baseline's score. " \
                     "Only whole or subject scope; no diff, replay, incremental reuse or score threshold.",
        takes_options: true,
        exit_codes: { 0 => "Clean check, proposal written or accepted.",
                      1 => "New, changed or unmatched survivors, or a score drop beyond --epsilon.",
                      2 => "Invalid configuration, incompatible baseline or rejected acceptance.",
                      3 => "Incomplete execution or tool failure." },
        examples: [["Prepare a reasoned proposal",
                    "saboteur baseline propose --baseline baseline.json --proposal proposal.json"],
                   ["Publish reviewed reasons",
                    "saboteur baseline accept --baseline baseline.json --proposal proposal.json"],
                   ["Check fresh outcomes", "saboteur baseline check --baseline baseline.json"],
                   ["Also fail on a score drop of more than 2 points",
                    "saboteur baseline check --baseline baseline.json --epsilon 2"]]
      ),
      Command.new(
        name: "survivors",
        summary: "Browse a report's survivors in the terminal, read-only",
        description: "Reads the Stryker JSON report without booting the project or rerunning tests. " \
                     "Lists every survivor with rank, file, line, operator, digest and classification " \
                     "label; filters with --file, --operator and --label; --ranked uses the report's ranked " \
                     "findings order. --show DIGEST prints the diff, the exact replay command and an " \
                     "ignore-file entry template for that mutant. It never edits the ignore file.",
        takes_options: false,
        exit_codes: { 0 => "Survivors listed or shown (including none).",
                      2 => "Missing, malformed or unreadable report; bad arguments." },
        examples: [["List survivors from the last run", "saboteur survivors .saboteur/report.json"],
                   ["Review-priority order", "saboteur survivors .saboteur/report.json --ranked"],
                   ["Diff, replay command and ignore template for one mutant",
                    "saboteur survivors .saboteur/report.json --show 1a2b3c4d5e6f7a8b"]]
      ),
      Command.new(
        name: "badge",
        summary: "Print a shields.io endpoint badge over the opt-in score history",
        description: "Reads the score history JSONL (c.score_history, or --history PATH) and prints one " \
                     "shields.io endpoint badge JSON for the latest record: label, mutation score and " \
                     "color (brightgreen at or above --high, default 80; yellow at or above --low, " \
                     "default 60; red below). --output PATH writes the file instead of printing. An " \
                     "incomplete latest record is refused unless --mark-partial labels the badge as " \
                     "partial. No hosted service, no project boot, no tests run.",
        takes_options: true,
        exit_codes: { 0 => "Badge JSON written.",
                      2 => "No history path or unexpected arguments.",
                      3 => "Empty or unreadable history, an incomplete record without --mark-partial, " \
                           "or no tested mutants." },
        examples: [["Badge the recorded score", "saboteur badge"],
                   ["Write the badge file CI uploads", "saboteur badge --output .saboteur/badge.json"]]
      ),
      Command.new(
        name: "trend",
        summary: "Print the score trend over the opt-in score history",
        description: "Reads the score history JSONL (c.score_history, or --history PATH) and prints the " \
                     "latest record next to the most recent comparable one (same configured selection, " \
                     "operator policy and a complete run), with the covered-score change in percentage " \
                     "points. With no comparable earlier record it says so instead of inventing a " \
                     "delta. No hosted service, no project boot, no tests run.",
        takes_options: true,
        exit_codes: { 0 => "Trend printed.",
                      2 => "No history path or unexpected arguments.",
                      3 => "Empty or unreadable history." },
        examples: [["Show the latest score and its change", "saboteur trend"]]
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
      ),
      Command.new(
        name: "agent-skill",
        summary: "Print instructions for AI coding agents to paste into AGENTS.md or CLAUDE.md",
        description: "Prints a short Markdown block that tells an agent when to run saboteur, how to read " \
                     "`saboteur run --agent`, and how to handle survivors.",
        takes_options: false,
        exit_codes: nil,
        examples: [["Add the agent instructions to your repo", "saboteur agent-skill >> AGENTS.md"]]
      )
    ].freeze

    AGENT_EXIT_CODES = "  With --agent the codes are stricter: 0 only when the run was complete and clean; " \
                       "1 survivors to review;\n  2 usage or config error; 3 incomplete (no coverage, caps, errors, " \
                       "a budget stop before any mutant ran, nothing selected) or tool failure."

    FILES = [
      ["config/saboteur.rb", "Settings as Ruby (Saboteur.configure). Command line options override it."],
      ["config/saboteur_ignore.rb", "Accepted survivors: mutation digests with subject and a required reason."],
      [".saboteur/report.json", "Stryker mutation-testing-report-schema JSON (--json changes the path)."],
      [".saboteur/report.html", "Self-contained HTML report (--html changes the path)."],
      [".saboteur/", "Cache: coverage map and incremental verdicts. Safe to delete between runs; stop the run first."]
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

    # run, audit and pr share one exit-code table; the overview keeps every
    # command's section but carries the agent note only on the first table
    # that shares it, so the phrase appears exactly once.
    def exit_code_sections
      noted = []
      @commands.select(&:exit_codes).map do |command|
        first = noted.none? { |codes| codes.equal?(command.exit_codes) }
        noted << command.exit_codes
        exit_codes_section(command.exit_codes, command.name, agent_note: first)
      end
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

    def exit_codes_section(codes, command_name = nil, agent_note: true)
      rows = codes.map { |code, meaning| "  #{code}  #{meaning}" }
      title = command_name ? "EXIT CODES (saboteur #{command_name})" : "EXIT CODES"
      note = agent_note && codes.equal?(EXIT_CODE_MEANINGS) ? "#{AGENT_EXIT_CODES}\n" : ""
      "#{title}\n#{rows.join("\n")}\n#{note}"
    end

    def config_section
      rows = Config::DEFAULTS.map { |key, value| "  c.#{key} = #{describe_default(value)}" }
      intro = "Every setting with its default value, as a Ruby assignment. Unknown settings are an error."
      "CONFIG FILE (config/saboteur.rb)\n#{intro}\n#{rows.join("\n")}\n"
    end

    # Ruby literals, so a copied line loads as the same value: inspect prints
    # nil as "nil" (JSON would print null, which is not Ruby) and quotes
    # strings and arrays the way Ruby reads them back.
    def describe_default(value)
      value.inspect
    end

    def files_section
      "FILES\n#{FILES.map { |path, meaning| "  #{path.ljust(files_width)}  #{meaning}" }.join("\n")}\n"
    end

    def files_width
      FILES.map { |path, _| path.length }.max
    end
  end
end
