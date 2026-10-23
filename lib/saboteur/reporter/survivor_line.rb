# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "survivor_classification"

module Saboteur
  module Reporter
    # The one-line collapsed survivor shape shared by the quiet report and
    # the default findings list: path:line subject, the statement's label
    # and the digest of the mutant carrying that label (0.12.4 review,
    # finding 1), sibling mutants collapsed to a count (#1126/#1133).
    module SurvivorLine
      module_function

      def collapsed(path, line, subject_id, results)
        first = SurvivorClassification.representative(results)
        rest = results - [first]
        label = SurvivorClassification.group_label(results)
        text = "#{path}:#{line} #{subject_id}#{" [#{label}]" if label} - #{first.digest}"
        rest.any? ? "#{text} (+#{rest.size} more)" : text
      end
    end
  end
end
