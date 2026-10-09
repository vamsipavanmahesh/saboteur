# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Plain-text summary: counts per status, score, timings, skip reasons,
    # errors, then a unified diff for each survivor.
    class Terminal
      MAX_ERRORS = 10

      def initialize(out)
        @out = out
      end

      def call(report)
        summary(report)
        warnings(report)
        errors(report)
        survivors(report)
      end

      private

      def summary(report)
        @out.puts "saboteur #{VERSION}: #{report.subjects.size} subjects, #{report.results.size} mutants, " \
                  "wall #{format('%.2f', report.wall_time)} s"
        @out.puts status_line(report)
        details(report)
      end

      def status_line(report)
        c = report.counts
        survived = "survived #{c[:survived]}"
        ignored = report.survivors.size - report.unignored_survivors.size
        survived += " (#{ignored} ignored)" if ignored.positive?
        "killed #{c[:killed]}  #{survived}  timeout #{c[:timeout]}  error #{c[:error]}  skipped #{c[:skipped]}"
      end

      def details(report)
        score = report.score
        @out.puts "score #{score ? format('%.1f %%', score * 100) : 'n/a'} " \
                  "(killed+timeout)/(killed+survived+timeout); errors and skips excluded"
        mean = report.mean_runtime
        @out.puts "mean time per executed mutant #{format('%.3f', mean)} s" if mean
        @out.puts "invalid mutations dropped (did not parse): #{report.invalid_mutations}" if
          report.invalid_mutations.positive?
        report.skip_reasons.each { |reason, count| @out.puts "skipped: #{reason}: #{count}" }
      end

      def warnings(report)
        report.warnings.each { |warning| @out.puts "warning: #{warning}" }
      end

      def errors(report)
        errored = report.results.select { |result| result.status == :error }
        return if errored.empty?

        @out.puts "\nErrors (not counted as killed):"
        errored.first(MAX_ERRORS).each do |result|
          @out.puts "  #{result.subject.id} #{result.mutation.operator} #{result.digest}: " \
                    "#{result.reason.to_s.lines.first&.strip}"
        end
        @out.puts "  ... #{errored.size - MAX_ERRORS} more" if errored.size > MAX_ERRORS
      end

      def survivors(report)
        return if report.survivors.empty?

        @out.puts "\nSurvivors:"
        report.survivors.each do |result|
          location = "#{relative(result.subject.file, report.root)}:#{result.subject.start_line}"
          @out.puts "\n#{result.subject.id} #{result.mutation.operator} #{result.digest} #{location}"
          @out.puts "ignored: #{result.ignored}" if result.ignored
          @out.puts result.diff(root: report.root)
        end
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
