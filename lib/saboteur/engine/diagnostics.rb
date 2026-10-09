# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # What a run has to say besides results: warnings for the report, the
    # count of mutations dropped for not parsing, and progress marks.
    class Diagnostics
      MARKS = { killed: ".", survived: "S", timeout: "T", error: "E" }.freeze

      attr_reader :warnings, :invalid_mutations

      def initialize(err)
        @err = err
        @warnings = []
        @invalid_mutations = 0
      end

      def warn(message)
        @warnings << message
      end

      def count_invalid_mutation
        @invalid_mutations += 1
      end

      def inform(message)
        @err.puts("saboteur: #{message}")
      end

      def progress(result)
        @err.print(MARKS.fetch(result.status, "?"))
        @err.flush
      end

      def finish_progress
        @err.puts
      end
    end
  end
end
