# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # A threshold or mutant-count gate judges the score, so a path that
    # narrows what the score covers (a partially mapped --since run, #370)
    # must keep its hard stop instead of green-lighting the change.
    module GatedRun
      private

      def gated?
        config["threshold"] || Gates.new(config).any?
      end
    end
  end
end
