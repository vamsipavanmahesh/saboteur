# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "suite_partition"

module Saboteur
  class Engine
    # A baseline check split like the coverage build (--coverage-parts N):
    # the same disjoint spec-file parts run as children at once, each over
    # its own files. Uses the guard's @config, @integration, @supervisor,
    # @diagnostics, @part and settled/phase_timeout/log_path.
    #
    # The check's contract is unchanged. Every part must pass, and the
    # examples the parts executed together must be exactly the loaded
    # suite's (the guard compares them before it accepts the pass). What a
    # split no longer shows is a failure that needs the whole suite in one
    # process.
    module BaselineParts
      private

      # The parts the coverage build would use. One part (or none, for an
      # adapter that lists no spec files) means the ordinary single check.
      def baseline_parts
        Engine::SuitePartition.parts(@integration.test_files, @config["coverage_parts"])
      end

      def check_parts(number, parts)
        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("baseline check #{number} (#{parts.size} parts)")
                                .watch(log_path(number, 0))
        admitted = phase_timeout
        results = @supervisor.run_many(parts.size, timeout: admitted, on_tick: heartbeat.method(:tick),
                                                   label: "baseline child died during setup/run") do |writer, slot|
          ENV["TEST_ENV_NUMBER"] = slot.zero? ? "" : (slot + 1).to_s
          record(writer, number, files: parts[slot], part: slot)
        end
        joined(results.each_with_index.map { |result, slot| settled(number, result, admitted, part: slot) })
      end

      # What the guard's checks read: the first failing part's own result
      # (its failures and hint; @part names its log), or a pass carrying
      # every example the parts executed.
      def joined(datas)
        @part = datas.index { |data| !(data["passed"] && data["failed"].empty?) }
        return datas[@part] if @part

        { "passed" => true, "failed" => [], "executed" => datas.flat_map { |data| data["executed"] } }
      end
    end
  end
end
