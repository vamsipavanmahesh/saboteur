# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/score_history"

module Saboteur
  class CLI
    # Finished-run reporting shared by text and agent modes.
    module RunReporting
      private

      def text_run(report)
        @err.puts
        Reporter::Terminal.new(@out, verbose: @verbose || false, color: @color || :auto).call(report)
        Reporter::Replay.new(@out).call(report) if options[:id]
        code = exit_code(report)
        # The JSON carries the exit cause an outer harness trusts, so it is
        # the completion evidence for the whole run: write it only after
        # every other fallible reporting stage, or a late failure would
        # leave a fresh, misleading report behind.
        write_html(report)
        record_history(report)
        write_json(report, exit_cause(report, code))
        code
      end

      def agent_run(arguments)
        tree = WorkingTree.new(config.root, ignored: config.output_paths).state
        report = stdout_on_stderr { Engine.new(config, **arguments).call }
        payload = Reporter::Agent.call(report, agent_provenance(report, tree))
        rendered = Reporter::Agent.render(payload)
        # Same publish order as text_run: the JSON is the completion
        # evidence, so it is written only after every other fallible stage,
        # including the agent payload itself.
        write_html(report, announce: false)
        record_history(report)
        write_json(report, agent_exit_cause(report, payload), announce: false)
        @out.print(rendered)
        Reporter::Agent.exit_code(payload)
      end

      def record_history(report)
        path = config.path("score_history")
        return unless path

        tree = WorkingTree.new(config.root, ignored: config.output_paths).state
        scope = config.to_h.except("json_report", "html_report", "score_history", "cache_dir")
        message = Reporter::ScoreHistory.new(path).append(report, head: tree.head, scope: scope)
        @err.puts("saboteur: #{message}")
      end
    end
  end
end
