# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The examples an order-dependent spec file needs, in the order RSpec
    # defines them: for each file with a covering example, every example from
    # the start of the file through its last covering example. Later examples
    # cannot change earlier ones, so this is the smallest run that keeps
    # whatever state the earlier examples leave behind.
    class DefinedOrderPrefix
      ID_PATTERN = /\A(?<file>.*)\[(?<path>[\d:]+)\]\z/

      # every_test: all example ids the map knows, in any order.
      def initialize(every_test)
        @every_test = every_test
      end

      # The prefix for the covering examples; nil when it adds nothing to
      # what already ran (an id that is not an RSpec id included).
      def for(covering)
        parsed = covering.map { |id| parse(id) }
        return nil if parsed.any?(&:nil?)

        prefix = parsed.group_by(&:first).flat_map { |file, entries| file_prefix(file, entries.map(&:last).max) }
        prefix == covering ? nil : prefix
      end

      private

      def file_prefix(file, last_position)
        in_file = @every_test.filter_map { |id| (entry = parse(id)) && entry.first == file ? entry : nil }
        through = in_file.select { |entry| (entry.last <=> last_position) <= 0 }.sort_by(&:last)
        through.map { |entry| "#{file}[#{entry.last.join(':')}]" }
      end

      def parse(id)
        match = ID_PATTERN.match(id)
        match && [match[:file], match[:path].split(":").map(&:to_i)]
      end
    end
  end
end
