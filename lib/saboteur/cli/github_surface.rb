# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/github_annotations"

module Saboteur
  class CLI
    # The GitHub CI surface (PR12): workflow-command annotations on stdout
    # after the text report. Auto-detected on GitHub Actions; --format
    # github forces them, --format markdown keeps only the step summary.
    # Never changes the exit code or the text report.
    module GithubSurface
      private

      def emit_github_annotations(report, engine)
        return unless github_annotations?

        Reporter::GithubAnnotations.new(@out, replay_command: survivor_replay_command(report, engine)).call(report)
      end

      def github_annotations?
        return true if @format == "github"
        return false if @format == "markdown"

        ENV["GITHUB_ACTIONS"] == "true"
      end
    end
  end
end
