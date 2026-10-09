# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

module Saboteur
  module Execution
    # What a mutant child tells its supervisor, one JSON object per line on
    # a pipe. Every message carries the protocol version.
    #
    #   started  the mutated method is in place; tests are about to run
    #   result   passed, failed (ids), executed (ids), runtime, exited (status
    #            when a test called exit)
    #   error    message, backtrace: the harness failed, not the tests
    #
    # A child that dies after "started" without "result" crashed while its
    # tests ran; one that dies before "started" crashed while loading.
    module Protocol
      VERSION = 1

      module_function

      def emit(io, event, **fields)
        io.write("#{JSON.generate(v: VERSION, event: event, **fields)}\n")
        io.flush
      rescue IOError, SystemCallError
        nil
      end

      # Events in order; lines that are not this protocol's are ignored.
      def parse(payload)
        payload.each_line.filter_map do |line|
          message = JSON.parse(line)
          message if message.is_a?(Hash) && message["v"] == VERSION
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
