# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "io/console"
require "tempfile"

require_relative "../reporter/palette"

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
      MARK_TOKENS = { "." => :dim, "S" => :fail, "T" => :warn, "E" => :fail, "L" => :fail }.freeze
      # Readback whitelist: mutant children inherit the progress fd and can
      # write arbitrary bytes, so only known mark letters come back out.
      READBACK_GLYPHS = (MARK_TOKENS.keys + ["?"]).freeze
      # s:skipped never prints a glyph: skipped mutants never reach
      # progress (see start_progress); the letter is legend-only.
      LEGEND = ".:killed S:survived T:timeout E:error s:skipped L:resource limit"

      # Chunk sizing: leave room for the "  (n/total ...)" suffix, never
      # below the floor.
      CHUNK_MARGIN = 10
      CHUNK_FLOOR = 40
      DEFAULT_WIDTH = 80

      GenerationEvent = Data.define(:file, :subject, :source, :operator, :reason)
      Omission = Data.define(:subject, :count, :limit)
      DiscoveryFailure = Data.define(:file, :reason)

      attr_reader :warnings, :live_announced, :invalid_mutations, :generation_events, :omissions, :discovery_failures,
                  :hazard_suppressions, :inline_suppressions, :verbose, :quiet_start

      def initialize(err, verbose: false, palette: nil, quiet_start: true)
        @err = err
        @verbose = verbose
        @quiet_start = quiet_start
        @palette = palette || Reporter::Palette.for(err)
        @warnings = []
        @invalid_mutations = 0
        @generation_events = []
        @live_announced = []
        @omissions = []
        @discovery_failures = []
        @hazard_suppressions = 0
        @inline_suppressions = []
        @erb_template_skips = []
        @erb_template_note_emitted = false
      end

      # Every warning passes through here once: repository-controlled text
      # (file names, patterns, thread names, error text) cannot start a CI
      # workflow command on a line of its own, whichever site built it
      # (#834). Already escaped text is unchanged.
      def warn(message)
        @warnings << Text.display_safe_lines(message)
      end

      # Warnings built elsewhere (the ignore file's, the custom map's, a
      # child's): each goes through #warn, so none skips the escaping.
      def add_warnings(messages)
        messages.each { |message| warn(message) }
        nil
      end

      # ERB generator templates (Rails generators carry `.rb` files with ERB
      # interpolation, conventionally under `lib/generators/**/templates/`)
      # can never parse as plain Ruby, so they can never hold mutation
      # subjects (#372). One summarized note per run replaces the per-file
      # parse warning every discovery pass used to print; a real syntax
      # error in a plain Ruby file still warns per file.
      def record_erb_template_skip(file, root:)
        relative = file.to_s.delete_prefix("#{root}/")
        @erb_template_skips << relative.freeze unless @erb_template_skips.include?(relative)
        return if @erb_template_note_emitted

        @erb_template_note_emitted = true
        warn("skipping ERB template files that cannot parse as Ruby " \
             "(for example #{relative}); templates are not mutation subjects")
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

      # The selection and the test inference each walk the same changed
      # files in one run; a failure either of them finds is recorded once.
      def record_discovery_failure(file, reason:)
        failure = DiscoveryFailure.new(file: file.to_s.dup.freeze, reason: reason.to_s.dup.freeze)
        @discovery_failures << failure unless @discovery_failures.include?(failure)
      end

      # A mutant the hazard guard refused to generate (issue #102): counted
      # for the summary and recorded like any other generation event.
      def record_hazard_suppression(subject, mutation)
        @hazard_suppressions += 1
        record_generation(subject, source: "hazard_guard", operator: mutation.operator, reason: "hazardous")
      end

      def record_inline_suppression(subject, mutation, directive)
        @inline_suppressions << {
          file: subject.file, line: directive.line, subject: subject.id,
          operator: mutation.operator, reason: directive.reason,
          digest: mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
        }
      end

      def record_omission(subject, count:, limit:)
        @omissions << Omission.new(subject: subject.id.dup.freeze, count: count, limit: limit)
      end

      def inform(message)
        @err.puts("saboteur: #{Text.display_safe_lines(message)}")
      end

      # Chatter the default view folds into the quiet-start lines;
      # --verbose prints it byte-for-byte as before.
      def detail(message)
        inform(message) if @verbose || !@quiet_start
      end

      # A selection explanation the default view carries as one dim
      # summary line: the full text stays in report.warnings for machine
      # consumers and counts as announced, so it is not reprinted at the
      # end of the run.
      def announce_demoted(message)
        safe = Text.display_safe_lines(message)
        warn(safe)
        @live_announced << safe
      end

      # The quiet start: three lines, then progress. --verbose keeps
      # today's chatter instead and never prints these.
      def quiet_start_header(scope:, seed:, operators:)
        return if @verbose || !@quiet_start

        dot = @palette.glyph(:middot)
        line = "saboteur #{Saboteur::VERSION} #{dot} #{scope} #{dot} seed #{seed}"
        line += " #{dot} #{operators} operators (--list-operators)" if operators
        @err.puts(@palette.paint(:dim, line))
      end

      def quiet_baseline(passes:, elapsed:, tests:, cached:)
        return if @verbose || !@quiet_start

        check = @palette.paint(:pass, @palette.glyph(:check))
        suffix = cached ? " (cached)" : ""
        line = "#{check} baseline green (#{passes} #{passes == 1 ? 'pass' : 'passes'}, " \
               "#{format('%.1f', elapsed)}s)  #{check} coverage map: #{tests} " \
               "#{tests == 1 ? 'test' : 'tests'}#{suffix}"
        @err.puts(line)
      end

      def quiet_inference(spec_count)
        return if spec_count.nil? || @verbose || !@quiet_start

        files = spec_count == 1 ? "spec file" : "spec files"
        @err.puts(@palette.paint(:dim, "spec inference: #{spec_count} #{files} (details: --verbose)"))
      end

      # --verbose: one line per finished subject with its result marks, so a
      # survivor is attributable to a method as soon as the subject
      # completes, before the whole run ends (#262).
      def subject_progress(subject, results)
        return unless @verbose
        return if results.empty?

        marks = results.map { |result| painted_mark(MARKS.fetch(result.status, "?")) }.join
        inform("#{subject.id}  #{marks}")
      end

      # A message that is both a report warning and a stderr note. The
      # terminal does not reprint it at the end of the run (#605), but it
      # stays in report.warnings: JSON, HTML and agent consumers discard
      # stderr and must still see it.
      def announce(message)
        safe = Text.display_safe_lines(message)
        warn(safe)
        inform(safe)
        @live_announced << safe
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
        @glyphs = +""
        @err.puts(@palette.paint(:dim, LEGEND))
      end

      def progress(result)
        mark = MARKS.fetch(result.status, "?")
        return plain_progress(painted_mark(mark)) unless @progress_file

        done = record_progress(mark)
        if progress_on_terminal?
          @glyphs << mark
          @glyphs.size >= chunk_width ? commit_chunk(done) : redraw_line(done)
        elsif (done % chunk_width).zero?
          commit_file_chunk(done - chunk_width, chunk_width, done)
        end
        @err.flush
      end

      def painted_mark(mark)
        token = MARK_TOKENS[mark]
        token ? @palette.paint(token, mark) : mark
      end

      def finish_progress
        return unless @progress_file

        size = @progress_file.size
        pending = size % chunk_width
        commit_file_chunk(size - pending, pending, size) if pending.positive?
        @progress_file.close!
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

      def chunk_width
        columns = begin
          @err.winsize[1] if @err.respond_to?(:winsize)
        rescue SystemCallError
          nil
        end
        [(columns || DEFAULT_WIDTH) - CHUNK_MARGIN, CHUNK_FLOOR].max
      end

      def painted_glyphs
        @glyphs.each_char.map { |glyph| painted_mark(glyph) }.join
      end

      def redraw_line(done)
        @line_open = true
        @err.print("\r\e[K#{painted_glyphs}  #{@palette.paint(:dim, progress_summary(done))}")
      end

      def commit_chunk(done)
        @err.print("\r\e[K#{painted_glyphs}  #{@palette.paint(:dim, progress_summary(done))}\n")
        @glyphs.clear
      end

      # Piped chunks and the final partial chunk come from the progress
      # file, not the buffer: workers each buffer only their own marks,
      # while the shared file the workers inherit holds every mark.
      def commit_file_chunk(start, length, done)
        @err.print("\r\e[K") if @line_open
        @err.print("#{painted_file_glyphs(start, length)}  #{@palette.paint(:dim, progress_summary(done))}\n")
      end

      # binread caps at both +length+ (the recorded mark count) and EOF,
      # so a short or padded file cannot leak extra glyphs.
      def painted_file_glyphs(start, length)
        bytes = File.binread(@progress_file.path, length, start)
        bytes.each_char.filter_map { |glyph| painted_mark(glyph) if READBACK_GLYPHS.include?(glyph) }.join
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
