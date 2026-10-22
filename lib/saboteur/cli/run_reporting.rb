# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/score_history"
require_relative "../reporter/history_reader"
require_relative "../reporter/history_paths"

module Saboteur
  class CLI
    # Finished-run reporting shared by text and agent modes.
    module RunReporting
      private

      def text_run(report, engine)
        @err.puts
        # Classify before printing: the terminal's closing verdict line names
        # the exit and its reason, so the code must be known up front. The
        # gate and skip notes exit_code writes to @err now precede the
        # report instead of following it.
        code = exit_code(report)
        Reporter::Terminal.new(@out, verbose: @verbose || false, quiet: @quiet || false, color: @color || :auto,
                                     overrides: config["palette"], threshold: config["threshold"],
                                     replay_command: survivor_replay_command(report, engine),
                                     all_mutants: options[:all_mutants] || false, details: options[:details] || false,
                                     exit_code: code, previous_score: previous_score, scope: scope_label,
                                     whole_suite_map: whole_suite_map_for(engine, report),
                                     run_map: engine&.run_coverage_map,
                                     baseline_gate: (baseline_gate(report) if config["baseline"])).call(report)
        Reporter::Replay.new(@out).call(report) if options[:id]
        # The JSON carries the exit cause an outer harness trusts, so it is
        # the completion evidence for the whole run: write it only after
        # every other fallible reporting stage, or a late failure would
        # leave a fresh, misleading report behind.
        validate_history
        html = write_html(report)
        record_history(report)
        validate_history
        json = write_json(report, exit_cause(report, code))
        announce_reports(json => "JSON", html => "HTML")
        code
      end

      def agent_run(arguments)
        tree = WorkingTree.new(config.root, ignored: config.ignored_tree_paths).state
        # The machine path is exempt from the noise diet: quiet_start: false
        # keeps agent stderr byte-identical to the pre-diet default output.
        engine = Engine.new(config, **arguments, quiet_start: false)
        report = stdout_on_stderr { engine.call }
        payload = Reporter::Agent.call(report, agent_provenance(report, tree, engine))
        rendered = Reporter::Agent.render(payload)
        # Same publish order as text_run: the JSON is the completion
        # evidence, so it is written only after every other fallible stage,
        # including the agent payload itself.
        validate_history
        write_html(report)
        record_history(report)
        validate_history
        write_json(report, agent_exit_cause(report, payload))
        @out.print(rendered)
        Reporter::Agent.exit_code(payload)
      end

      def execute_run
        validate_history
        # One palette per stream: stdout and stderr detect colour on their
        # own, so a forced terminal report still leaves piped progress plain.
        arguments = { err: @err,
                      palette: Reporter::Palette.for(@err, mode: @color || :auto, overrides: config["palette"]) }
        arguments[:digest] = options[:id] if options[:id]
        arguments[:capture_evidence] = true if config["baseline"]
        arguments[:evidence_files] = [config["baseline"]] if config["baseline"]
        return agent_run(arguments) if agent?

        # Text mode only: the engine prints a per-subject marks line when
        # --verbose is on (#262); --agent output stays as it is.
        engine = Engine.new(config, **arguments, verbose: @verbose || false, quiet: @quiet || false)
        text_run(engine.call, engine)
      end

      # The full replay command for a survivor digest: this run's own
      # selection options, assembled by the same code that writes the agent
      # follow-ups, so the user never reassembles them by hand (#261).
      # Computed lazily: only a run with survivors asks for it.
      # The headline's delta: the covered score of the last history record.
      # The history is auxiliary evidence (#296): anything unreadable simply
      # means no delta, since validate_history reports real corruption.
      def previous_score
        path = config.path("score_history")
        return unless path && File.exist?(path)

        Reporter::HistoryReader.read(path).last&.fetch("coveredScore", nil)
      rescue Error
        nil
      end

      def survivor_replay_command(report, engine)
        lambda do |digest|
          tree = WorkingTree.new(config.root, ignored: config.ignored_tree_paths).state
          Reporter::Agent::Commands.replay(agent_provenance(report, tree, engine), digest, capped: false,
                                                                                           report: report)
        end
      end

      # Writes the JSON report and returns its path, or nil when none is configured.
      #
      # An explicitly requested JSON report (--json, c.json_report) is the
      # completion evidence an outer harness trusts: a failed write fails
      # the run (exit 3), because a warning with exit 0 could leave a stale
      # or partial file at the path and present old results as this run's.
      # The default .saboteur/report.json is best-effort like the HTML
      # report and the score history (#296).
      def write_json(report, cause)
        path = config.path("json_report")
        return unless path

        Reporter::Stryker.new(path).call(report, exit_cause: cause,
                                                 score_gates: gates.score_gate_breakdowns(report))
        path
      rescue SystemCallError, IOError => e
        if config.explicit?("json_report")
          raise Error, "could not write the JSON report to #{path}: #{e.message} - " \
                       "any file at that path may be stale or incomplete"
        end

        warn_report_write_failure("JSON report", path, e)
      end

      def write_html(report)
        path = config.path("html_report")
        return unless path

        Reporter::Html.new(path).call(report)
        path
      rescue SystemCallError, IOError => e
        warn_report_write_failure("HTML report", path, e)
      end

      # An auxiliary report artifact that cannot be written - the tree is
      # read-only inside a sandboxed child, as in the dogfood's nested runs
      # (#296) - is a warning, not a run failure: the exit code belongs to
      # the results. The JSON report is not auxiliary; see write_json.
      def warn_report_write_failure(what, path, error)
        @err.puts "saboteur: could not write the #{what} to #{path} (#{error.message}); continuing without it"
        nil
      end

      def validate_history
        path = config.path("score_history")
        return unless path

        Reporter::HistoryPaths.validate(%w[score_history json_report html_report].map { |key| config.path(key) })
        Reporter::ScoreHistory.new(path).validate_existing
      end

      def record_history(report)
        path = config.path("score_history")
        return unless path

        tree = WorkingTree.new(config.root, ignored: config.ignored_tree_paths).state
        scope = config.selection_settings.except(*Config::OUTPUT_KEYS, *Config::PRESENTATION_KEYS)
        # Recording is an auxiliary artifact: when the file cannot be
        # written - read-only tree inside a sandboxed child (#296) - warn
        # and let the run exit by its results instead of failing as a tool
        # error. Only the write's IO failures are soft: validation,
        # integrity, record-size and lock failures (Saboteur::Error) stay
        # hard, because they say the history is unusable, not unwritable.
        message = begin
          Reporter::ScoreHistory.new(path).append(report, head: tree.head, scope: scope)
        rescue SystemCallError, IOError => e
          warn_report_write_failure("score history", path, e)
        end
        @err.puts("saboteur: #{message}") if message
      end
    end
  end
end
