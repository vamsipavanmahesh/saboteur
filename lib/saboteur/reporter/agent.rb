# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "agent_summary"
require_relative "agent_commands"

module Saboteur
  module Reporter
    # A small JSON summary for an AI agent that runs saboteur (`saboteur run --agent`).
    #
    # The payload stays under BYTE_BUDGET: it never embeds file sources or the full
    # Stryker report. It names the verdict, says plainly what was not covered, shows
    # the first few findings with short edit snippets, counts the rest, and points
    # at the commands and files that hold the full detail.
    #
    # Exit codes in this mode are stricter than the classic ones: 0 means the run
    # was complete and clean, nothing less.
    module Agent
      VERSION = 1
      BYTE_BUDGET = 8 * 1024
      FINDING_LIMIT = 3
      SNIPPET_LIMITS = [200, 80, 0].freeze
      WARNING_LIMIT = 3
      WARNING_LENGTH = 160

      EXIT_CLEAN = 0
      EXIT_REVIEW = 1
      EXIT_INVOCATION = 2
      EXIT_INCOMPLETE = 3

      # Where a verdict comes from: the exact selection and the state of the working
      # source before the run started. subjects, tests and sources are arrays.
      Provenance = Data.define(:ref, :seed, :head, :working_tree, :changed_files, :mode, :json_report, :subjects,
                               :tests, :sources, :config_path, :digest, :cache, :incremental)

      class << self
        def call(report, provenance)
          fit(report, provenance)
        end

        def render(payload)
          "#{JSON.pretty_generate(payload)}\n"
        end

        def exit_code(payload)
          payload.fetch(:exitCode)
        end

        # The payload for a run that never started or could not finish.
        def failure(message, exit_code)
          verdict = exit_code == EXIT_INVOCATION ? "invalid_invocation" : "tool_failure"
          { version: VERSION, status: "error", verdict: verdict, exitCode: exit_code,
            message: message.to_s[0, 500], next: { help: "saboteur help run" } }
        end

        private

        def fit(report, provenance)
          FINDING_LIMIT.downto(0) do |shown|
            SNIPPET_LIMITS.each do |snippet_limit|
              payload = Summary.build(report, provenance, shown, snippet_limit)
              return payload if render(payload).bytesize <= BYTE_BUDGET
            end
          end
          minimal(report, provenance)
        end

        # The last resort: fixed keys and short clipped values, so it always fits.
        def minimal(report, provenance)
          small = Summary.build(report, provenance, 0, SNIPPET_LIMITS.last)
          small.merge(warnings: [], next: {}, provenance: small[:provenance].slice(:seed, :workingTree, :mode),
                      incomplete: small[:incomplete].map { |reason| reason.slice(:reason, :count) })
        end
      end
    end
  end
end
