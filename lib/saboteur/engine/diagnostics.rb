# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # What a run has to say besides results: warnings for the report, the
    # count of mutations dropped for not parsing, and progress marks.
    class Diagnostics
      # See progress_heartbeat. Time-gated itself, so the supervisor can
      # call tick on every poll.
      class ProgressHeartbeat
        def initialize(diagnostics, label, interval: 30)
          @diagnostics = diagnostics
          @label = label
          @interval = interval
          @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @last_print = @started
        end

        def tick
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return if now - @last_print < @interval

          @last_print = now
          @diagnostics.inform("#{@label}: #{(now - @started).round} s elapsed")
        end
      end

      MARKS = { killed: ".", survived: "S", timeout: "T", resource_limit: "L", error: "E" }.freeze

      GenerationEvent = Data.define(:file, :subject, :source, :operator, :reason)
      Omission = Data.define(:subject, :count, :limit)
      DiscoveryFailure = Data.define(:file, :reason)

      attr_reader :warnings, :invalid_mutations, :generation_events, :omissions, :discovery_failures

      def initialize(err)
        @err = err
        @warnings = []
        @invalid_mutations = 0
        @generation_events = []
        @omissions = []
        @discovery_failures = []
      end

      def warn(message)
        @warnings << message
      end

      def count_invalid_mutation
        @invalid_mutations += 1
      end

      def record_generation(subject, source:, reason:, operator: nil)
        values = [subject.file, subject.id, source, operator, reason].map do |value|
          value.nil? ? nil : value.to_s.dup.freeze
        end
        @generation_events << GenerationEvent.new(*values)
      end

      def record_discovery_failure(file, reason:)
        @discovery_failures << DiscoveryFailure.new(file: file.to_s.dup.freeze, reason: reason.to_s.dup.freeze)
      end

      def record_omission(subject, count:, limit:)
        @omissions << Omission.new(subject: subject.id.dup.freeze, count: count, limit: limit)
      end

      def inform(message)
        @err.puts("saboteur: #{message}")
      end

      # A heartbeat for a long phase: the supervisor's wait loop calls tick
      # in the parent after the fork, so no extra thread is ever alive at
      # fork time. Prints "<label>: N s elapsed" about every interval
      # seconds, so a long phase does not look stuck.
      def progress_heartbeat(label, interval: 30)
        ProgressHeartbeat.new(self, label, interval: interval)
      end

      def progress(result)
        @err.print(MARKS.fetch(result.status, "?"))
        @err.flush
      end
    end
  end
end
