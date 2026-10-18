# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "score_history"
require_relative "history_record"

module Saboteur
  module Reporter
    # Read side of the append-only score history for `saboteur badge` and
    # `saboteur trend` (#474). Every record is re-validated on read and the
    # file discipline mirrors ScoreHistory: regular file, no symlink,
    # byte-capped lines, no repair of imported evidence.
    module HistoryReader
      module_function

      def read(path)
        records = []
        File.open(path, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) do |file|
          raise Error, "score history must be a regular file" unless file.stat.file?

          file.flock(File::LOCK_SH)
          limit = ScoreHistory::MAX_RECORD_BYTES
          while (line = file.gets(limit + 1))
            raise Error, "score history record exceeds byte limit" if line.bytesize > limit
            raise Error, "score history contains a truncated record" unless line.end_with?("\n")

            records << HistoryRecord.parse(line)
          end
        end
        records
      rescue SystemCallError, IOError => e
        raise Error, "score history cannot be read: #{e.message}"
      end

      # The ScoreHistory change rules: same record version, selection,
      # inventory and operator policy (a null policy never compares), both
      # runs complete.
      def comparable?(previous, current)
        previous["version"] == current["version"] &&
          previous["selection"] == current["selection"] &&
          previous["inventory"] == current["inventory"] &&
          previous["incomplete"].empty? && current["incomplete"].empty? &&
          !previous["operatorPolicy"].nil? && previous["operatorPolicy"] == current["operatorPolicy"]
      end
    end
  end
end
