# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/score_history"
require_relative "../reporter/history_paths"

module Saboteur
  class CLI
    # Finished-run reporting shared by text and agent modes.
    module RunReporting
      private

      def text_run(report, engine)
        @err.puts
        Reporter::Terminal.new(@out, verbose: @verbose || false, color: @color || :auto,
                                     replay_command: survivor_replay_command(report, engine)).call(report)
        Reporter::Replay.new(@out).call(report) if options[:id]
        code = exit_code(report)
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
        tree = WorkingTree.new(config.root, ignored: config.output_paths).state
        engine = Engine.new(config, **arguments)
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
        arguments = { err: @err }
        arguments[:digest] = options[:id] if options[:id]
        return agent_run(arguments) if agent?

        # Text mode only: the engine prints a per-subject marks line when
        # --verbose is on (#262); --agent output stays as it is.
        engine = Engine.new(config, **arguments, verbose: @verbose || false)
        text_run(engine.call, engine)
      end

      # The full replay command for a survivor digest: this run's own
      # selection options, assembled by the same code that writes the agent
      # follow-ups, so the user never reassembles them by hand (#261).
      # Computed lazily: only a run with survivors asks for it.
      def survivor_replay_command(report, engine)
        lambda do |digest|
          tree = WorkingTree.new(config.root, ignored: config.output_paths).state
          Reporter::Agent::Commands.replay(agent_provenance(report, tree, engine), digest)
        end
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

        tree = WorkingTree.new(config.root, ignored: config.output_paths).state
        scope = config.selection_settings.except("json_report", "html_report", "score_history", "cache_dir")
        message = Reporter::ScoreHistory.new(path).append(report, head: tree.head, scope: scope)
        @err.puts("saboteur: #{message}")
      end
    end
  end
end
