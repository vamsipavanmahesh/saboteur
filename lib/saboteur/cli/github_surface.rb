# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/github_annotations"
require_relative "../reporter/step_summary"

module Saboteur
  class CLI
    # The GitHub CI surface (PR12): workflow-command annotations on stdout
    # after the text report. Auto-detected on GitHub Actions; --format
    # github forces them and --format markdown keeps only the step summary,
    # written to $GITHUB_STEP_SUMMARY when it is set.
    # Never changes the exit code or the text report.
    module GithubSurface
      private

      def emit_github_surface(report, engine)
        emit_github_annotations(report, engine) if github_annotations?
        Reporter::StepSummary.new.call(report) if step_summary?
      end

      def emit_github_annotations(report, engine)
        Reporter::GithubAnnotations.new(@out, replay_command: survivor_replay_command(report, engine)).call(report)
      end

      def github_annotations?
        return true if @format == "github"
        return false if @format == "markdown"

        ENV["GITHUB_ACTIONS"] == "true"
      end

      def step_summary?
        return true if %w[github markdown].include?(@format)
        return false if @format

        ENV["GITHUB_ACTIONS"] == "true"
      end
    end
  end
end
