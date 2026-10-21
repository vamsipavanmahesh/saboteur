# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Timeouts count as killed in the score, but a slow test that times out
    # every mutant hides a real gap, so the findings area names them. One
    # line per timeout, ordered by file path then line like the survivors.
    class TimeoutList
      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def call(report)
        timed_out = report.results.select { |result| result.status == :timeout }
        return if timed_out.empty?

        # No leading blank of our own: the survivors section already ends
        # with one, and with no survivors this section opens the output.
        @out.puts @palette.paint(:warn, "Timeouts (#{timed_out.size}):")
        ordered(timed_out, report.root).each do |result|
          path = relative(result.subject.file, report.root)
          detail = @palette.paint(:dim, timeout_detail(result))
          @out.puts "  #{path}:#{MutationText.line(result)} #{result.subject.id} #{detail}"
        end
      end

      private

      def ordered(timed_out, root)
        timed_out.sort_by { |result| [relative(result.subject.file, root), MutationText.line(result)] }
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end

      # The engine records the mutant's configured deadline in the timeout
      # reason ("exceeded 6.52 s"), so the deadline is never hardcoded here.
      def timeout_detail(result)
        match = result.reason&.match(/exceeded ([\d.]+) s/)
        return "(#{result.mutation.operator})" unless match

        "(#{result.mutation.operator}, deadline #{format('%g', Float(match[1]))}s)"
      end
    end
  end
end
