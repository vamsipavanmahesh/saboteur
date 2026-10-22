# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/history_reader"

module Saboteur
  class CLI
    # `saboteur badge` and `saboteur trend` (#474): a local README badge and
    # a trend read-out over the opt-in score history, no hosted service.
    module HistoryCommand
      DEFAULT_HIGH = 80.0
      DEFAULT_LOW = 60.0

      def badge_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur badge [--history PATH] [--output PATH] [--mark-partial] " \
                        "[--high PERCENT] [--low PERCENT]"
          opts.on("--history PATH", "Score history JSONL (default: c.score_history)") { |v| @history_path = v }
          opts.on("--output PATH", "Badge JSON destination (default: stdout)") { |v| @output = v }
          opts.on("--mark-partial", "Badge an incomplete run, labeled as partial") { @mark_partial = true }
          opts.on("--high PERCENT", Float, "brightgreen at or above (default #{DEFAULT_HIGH.to_i})") { |v| @high = v }
          opts.on("--low PERCENT", Float, "yellow at or above (default #{DEFAULT_LOW.to_i})") { |v| @low = v }
          define_color_options(opts)
        end
      end

      def trend_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur trend [--history PATH]"
          opts.on("--history PATH", "Score history JSONL (default: c.score_history)") { |v| @history_path = v }
          define_color_options(opts)
        end
      end

      private

      def history_command(command) = command == "badge" ? badge : trend

      def badge
        badge_parser.parse!(@argv)
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        write_badge(badge_payload(read_history.last))
        EXIT_OK
      rescue ConfigError, Error, SystemCallError => e
        history_failure(e)
      end

      def trend
        trend_parser.parse!(@argv)
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        print_trend(latest_pair)
        EXIT_OK
      rescue ConfigError, Error, SystemCallError => e
        history_failure(e)
      end

      def history_failure(error)
        @err.puts("saboteur: #{error.message}")
        error.is_a?(ConfigError) ? EXIT_USAGE : EXIT_TOOL
      end

      def latest_pair
        records = read_history
        current = records.last
        [records[0...-1].reverse.find { |record| Reporter::HistoryReader.comparable?(record, current) }, current]
      end

      def read_history
        records = Reporter::HistoryReader.read(history_path)
        if records.empty?
          raise Error,
                "score history is empty - record it first by running saboteur with c.score_history set"
        end

        records
      end

      def history_path
        @history_path ||= config.path("score_history")
        @history_path or raise UsageError, "no score history: pass --history PATH or set c.score_history"
      rescue ConfigError
        raise UsageError, "no score history: pass --history PATH or set c.score_history"
      end

      def badge_payload(record)
        partial = record["incomplete"].any?
        if partial && !@mark_partial
          raise Error, "the latest score history record is an incomplete run " \
                       "(#{record['incomplete'].map(&:inspect).join(', ')}) - " \
                       "badge evidence needs a complete run, or pass --mark-partial to label it"
        end
        score = record["coveredScore"]
        raise Error, "the latest score history record has no tested mutants" if score.nil?

        { schemaVersion: 1, label: partial ? "mutation score (partial)" : "mutation score",
          message: format("%.1f%%", score * 100), color: badge_color(score) }
      end

      def write_badge(payload)
        json = "#{JSON.generate(payload)}\n"
        return @out.print(json) unless @output

        File.write(@output, json)
        @out.puts(@output)
      end

      def badge_color(score)
        percent = score * 100
        return "brightgreen" if percent >= (@high || DEFAULT_HIGH)
        return "yellow" if percent >= (@low || DEFAULT_LOW)

        "red"
      end

      def print_trend((previous, current))
        ([previous].compact + [current]).each { |record| @out.puts(trend_line(record)) }
        unless previous && previous["coveredScore"] && current["coveredScore"]
          return @out.puts("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)")
        end

        delta = (current["coveredScore"] - previous["coveredScore"]) * 100
        @out.puts(format("covered score change %<delta>+.2f percentage points since %<since>s " \
                         "(same configured selection)", delta: delta, since: previous["date"]))
      end

      def trend_line(record)
        suffix = record["incomplete"].empty? ? "" : " (incomplete)"
        score = record["coveredScore"]
        "#{record['date']} #{record['commit']&.slice(0, 8) || '-'} " \
          "#{score.nil? ? 'no tested mutants' : format('%.1f%%', score * 100)}#{suffix}"
      end
    end
  end
end
