# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tempfile"

module Saboteur
  class Engine
    # What a run has to say besides results: warnings for the report, the
    # count of mutations dropped for not parsing, and progress marks.
    class Diagnostics
      # See progress_heartbeat. Time-gated itself, so the supervisor can
      # call tick on every poll. A phase whose child writes "N/M examples
      # finished" lines to a log (the baseline and coverage children do) can
      # be watched: the heartbeat then adds the count, the percentage and an
      # estimate of the time left to its elapsed-time line.
      class ProgressHeartbeat
        COUNT = %r{(\d+)/([1-9]\d*) examples finished}
        TAIL_BYTES = 4096

        def initialize(diagnostics, label, interval: 30)
          @diagnostics = diagnostics
          @label = label
          @interval = interval
          @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @last_print = @started
          @log = nil
        end

        # Reads progress from the end of this log on each print. Returns self.
        def watch(log_path)
          @log = log_path
          self
        end

        def tick
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return if now - @last_print < @interval

          @last_print = now
          elapsed = now - @started
          @diagnostics.inform("#{@label}: #{elapsed.round} s elapsed#{progress_note(elapsed)}")
        end

        private

        # ", 250/1000 examples (25 %), about 90 s left", or "" when the log has
        # no count yet. The estimate assumes examples take equally long, so it
        # is rough: slow examples late in the order make it too low.
        def progress_note(elapsed)
          done, total = examples_finished
          return "" if done.nil?

          note = ", #{done}/#{total} examples (#{(done * 100.0 / total).floor} %)"
          return note if done.zero? || done >= total

          "#{note}, about #{(elapsed * (total - done) / done).ceil} s left"
        end

        def examples_finished
          return unless @log

          tail = File.read(@log, TAIL_BYTES, [File.size(@log) - TAIL_BYTES, 0].max).to_s.scrub
          tail.scan(COUNT).last&.map(&:to_i)
        rescue SystemCallError
          nil
        end
      end

      MARKS = { killed: ".", survived: "S", timeout: "T", resource_limit: "L", error: "E" }.freeze
      LEGEND = ". killed  S survived  T timeout  L resource limit  E error"
      LINE_WIDTH = 50

      GenerationEvent = Data.define(:file, :subject, :source, :operator, :reason)
      Omission = Data.define(:subject, :count, :limit)
      DiscoveryFailure = Data.define(:file, :reason)

      attr_reader :warnings, :invalid_mutations, :generation_events, :omissions, :discovery_failures,
                  :hazard_suppressions

      def initialize(err)
        @err = err
        @warnings = []
        @invalid_mutations = 0
        @generation_events = []
        @omissions = []
        @discovery_failures = []
        @hazard_suppressions = 0
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

      # A mutant the hazard guard refused to generate (issue #102): counted
      # for the summary and recorded like any other generation event.
      def record_hazard_suppression(subject, mutation)
        @hazard_suppressions += 1
        record_generation(subject, source: "hazard_guard", operator: mutation.operator, reason: "hazardous")
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
