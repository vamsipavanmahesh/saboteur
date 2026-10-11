# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # A replay is an inspection too, regardless of the resulting verdict.
    class Replay
      def initialize(out)
        @out = out
      end

      def call(report)
        report.results.each do |result|
          @out.puts "\nReplay: #{result.subject.id} #{result.mutation.operator} #{result.digest} (#{result.status})"
          @out.puts result.diff(root: report.root)
          @out.puts "Selected tests:"
          result.covered_by.each { |name| @out.puts "  #{name}" }
          @out.puts "  none" if result.covered_by.empty?
        end
      end
    end
  end
end
