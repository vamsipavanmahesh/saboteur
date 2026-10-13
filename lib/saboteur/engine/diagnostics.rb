# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tempfile"

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
      LEGEND = ". killed  S survived  T timeout  L resource limit  E error"
      LINE_WIDTH = 50

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

      # Call before the workers fork. total is the number of mutants the run
      # may execute; mutants that are skipped or reused never report progress,
      # so the counter can end below total and the ETA errs on the long side.
      # The count lives in one file the workers inherit, so every worker adds
      # to the same number.
      def start_progress(total)
        @progress_total = total
        @progress_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @progress_file = Tempfile.new("saboteur-progress")
        @progress_file.binmode
        @progress_file.sync = true
        @err.puts("saboteur: progress #{LEGEND}") unless progress_on_terminal?
      end

      def progress(result)
        mark = MARKS.fetch(result.status, "?")
        return plain_progress(mark) unless @progress_file

        done = record_progress(mark)
        progress_on_terminal? ? terminal_progress(done) : ci_progress(mark, done)
        @err.flush
      end

      def finish_progress
        @err.puts if @progress_file && (progress_on_terminal? || @progress_file.size % LINE_WIDTH != 0)
        @progress_file&.close!
        @progress_file = nil
      end

      def progress_summary(done)
        return "#{done}/#{@progress_total}" unless @progress_total.to_i.positive?

        percent = (done * 100.0 / @progress_total).floor
        "#{done}/#{@progress_total} (#{percent}%)#{eta_text(done)}"
      end

      private

      def plain_progress(mark)
        @err.print(mark)
        @err.flush
      end

      def record_progress(mark)
        @progress_file.write(mark)
        @progress_file.size
      end

      def progress_on_terminal?
        @err.respond_to?(:tty?) && @err.tty?
      end

      def terminal_progress(done)
        @err.print("\r\e[Ksaboteur: #{progress_summary(done)}")
      end

      def ci_progress(mark, done)
        @err.print(mark)
        @err.print(" #{progress_summary(done)}\n") if (done % LINE_WIDTH).zero?
      end

      def eta_text(done)
        remaining = @progress_total - done
        return "" if remaining <= 0 || done.zero?

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @progress_started
        seconds = (elapsed / done * remaining).round
        " eta #{seconds / 60}m#{format('%02d', seconds % 60)}s"
      end
    end
  end
end
