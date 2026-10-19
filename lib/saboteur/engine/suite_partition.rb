# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Splits a suite's spec files into disjoint parts for parallel coverage
    # builds (#741). The sorted list is dealt round-robin, the rule
    # script/rspec-shard uses without weights, so every file lands in exactly
    # one part and the split depends only on the file list, never on load or
    # discovery order. A part that would be empty is not returned.
    class SuitePartition
      def self.parts(files, total)
        raise ArgumentError, "parts must be at least 1, got #{total}" if total < 1

        sorted = files.uniq.sort
        dealt = Array.new([total, sorted.size].min) { [] }
        sorted.each_with_index { |file, position| dealt[position % dealt.size] << file }
        dealt
      end
    end
  end
end
