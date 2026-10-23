# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Opinionated bundles (#244): pr is the fast changed-lines loop (one
    # baseline check, a 10-minute budget that fails an incomplete run),
    # audit is the whole project with both reports. Preset flags go first,
    # so an explicit flag after them wins on the usual last-flag rule.
    module Presets
      PRESETS = {
        "pr" => %w[--baseline-passes 1 --max-duration 10m],
        "audit" => %w[--all --operators all --baseline-passes 2 --json .saboteur/audit-report.json
                      --html .saboteur/audit-report.html]
      }.freeze

      # What a new user types first; there is no such command, the Rails
      # generator writes the starter files.
      SETUP_WORDS = %w[init install setup].freeze
      SETUP_HINT = "To set up a Rails app, run: bin/rails generate saboteur:install"

      # Preset flags that take a separate value token: the pairs a user
      # flag can override in the banner (#666).
      VALUE_FLAGS = %w[--baseline-passes --max-duration --since --operators --json --html].freeze

      private

      # The pr preset's base when the user names none: origin's default
      # branch, so a repo on master works without an argument (#1191).
      # A local-only clone has no origin/HEAD, so main stands and the
      # not-a-commit hint lists the branches it does have.
      def default_base_ref
        Selection::GitDiff.default_branch(Dir.pwd) || "main"
      end

      def preset_or_usage_error(command)
        return preset(command) if PRESETS.key?(command)

        # A typo'd command is not a run: say so before the usage line.
        @err.puts("unknown command: #{command}. Run 'saboteur help' for the commands.") if command
        @err.puts(SETUP_HINT) if SETUP_WORDS.include?(command)
        usage_error
      end

      def preset(name)
        flags = PRESETS.fetch(name).dup
        if name == "pr"
          ref = @argv.first.nil? || @argv.first.start_with?("-") ? default_base_ref : @argv.shift
          flags += ["--since", ref]
        end
        # An explicit scope beats the injected whole-suite --all, which
        # would otherwise reject the combination: named tests, and the
        # deprecated inference alias (#245).
        explicit_scope = @argv.any? { |arg| arg == "--test" || arg.start_with?("--test=") || arg == "--guess-tests" }
        flags.delete("--all") if explicit_scope
        @err.puts("saboteur: preset '#{name}': #{preset_banner(flags).join(' ')} (explicit flags override)")
        @argv = flags + @argv
        run_command
      end

      # The banner is the reader's only record of the effective settings,
      # so a preset flag the user also passed shows the user's spelling -
      # the later occurrence wins (#666). Flags the user did not override
      # print as the preset declares them.
      def preset_banner(flags)
        overrides = user_flag_overrides
        banner = []
        index = 0
        while index < flags.size
          if VALUE_FLAGS.include?(flags[index])
            banner.concat(overrides.fetch(flags[index], [flags[index], flags[index + 1]]))
            index += 2
          else
            banner << flags[index]
            index += 1
          end
        end
        banner
      end

      # Each long flag the user passed, mapped to its effective spelling:
      # the last occurrence, verbatim, with its separate value token when
      # the flag takes one.
      def user_flag_overrides
        overrides = {}
        @argv.each_with_index do |arg, index|
          name = arg[/\A--[^=]+/] or next
          if arg.include?("=")
            overrides[name] = [arg]
          elsif VALUE_FLAGS.include?(name) && @argv[index + 1]
            overrides[name] = [name, @argv[index + 1]]
          end
        end
        overrides
      end
    end
  end
end
