# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # What the clean screen's header and reports line need from the run: the
    # real scope, the HTML report's path when it was written, and the phase costs.
    module CleanScreenContext
      private

      def clean_screen_context(html_path, report)
        { **report.phase_stats, scope: config["since"] ? "--since #{config['since']}" : "whole project",
                                html_report: html_path && relative_to_root(html_path) }
      end

      def relative_to_root(path)
        File.expand_path(path).delete_prefix(File.join(File.realpath(config.root), ""))
      end
    end
  end
end
