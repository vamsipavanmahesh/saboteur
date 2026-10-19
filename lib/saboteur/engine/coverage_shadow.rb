# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "securerandom"

module Saboteur
  class Engine
    # CoverageStore's opt-in shadow step (#46): after a cache miss, rebuild
    # the map partially from the last one and compare it with the full map
    # the run just built. Uses the store's @config, @root, @integration,
    # @supervisor and @diagnostics, and its record and map_from.
    module CoverageShadow
      private

      # The opt-in shadow run (#46) needs the single whole-suite build: a
      # scoped or parted map is not what a partial rebuild is compared with.
      def shadow?
        @config["partial_coverage"] == "shadow" && @config["cache"] && @config["tests"].empty? && @parts == 1
      end

      # Never stops a run: the full map is already built and is the one used.
      # Writes shadow-<map key>.json beside the map, with the seconds the full
      # build and the partial rerun took, and warns on a mismatch.
      def shadow(files, full_map, note, build_seconds)
        cache = @config.path("cache_dir")
        base = CoverageInputsSnapshot.latest(cache, @root)
        base_map = base && Selection::CoverageMap.load(CoverageInputsSnapshot.map_path(cache, base["map_key"]))
        return unless base_map

        rerun_seconds = nil
        report = ShadowRun.call(base: base, base_map: base_map, current: note.current, full_map: full_map,
                                invalidation: shadow_invalidation(base_map, files), fallback_files: files,
                                rerun: lambda { |specs, seed|
                                  from = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                                  shadow_rerun(files, specs, seed).tap do
                                    rerun_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - from
                                  end
                                }, clean: method(:shadow_clean))
        report = report.merge("full_build_seconds" => build_seconds.round(2),
                              "rerun_seconds" => rerun_seconds&.round(2))
        save_shadow_report(cache, report, cache_key(files))
      rescue StandardError => e
        @diagnostics.warn("partial coverage shadow run failed (the full map is used): #{shadow_clean(e.message)}")
      end

      def shadow_invalidation(base_map, files)
        PartialInvalidation.new(map: base_map, root: @root, included: files.map(&method(:relative)),
                                spec_files: @integration.test_files.map(&method(:relative)),
                                status_file: @integration.status_file?(@root))
      end

      def relative(file)
        file.delete_prefix("#{@root}/")
      end

      # The stale spec files, run once in a child with the seed the base map
      # was built with, over exactly the runnable spec files named. It writes
      # the store's usual map build log, which the full build is done with.
      def shadow_rerun(files, specs, seed)
        Execution::ForkReadiness.prepare_heap
        admitted = build_timeout
        result = @supervisor.run(timeout: admitted, label: "coverage child died during the shadow rerun") do |writer|
          record(writer, files, only: specs.map { |file| File.join(@root, file) }, seed: seed)
        end
        map_from(result, admitted)
      end

      def save_shadow_report(cache, report, key)
        target = File.join(cache, "shadow-#{key}.json")
        temp = "#{target}.#{SecureRandom.hex(8)}.tmp"
        begin
          File.open(temp, "wx", 0o600) { |out| out.write(JSON.pretty_generate(report)) }
          File.rename(temp, target)
        ensure
          FileUtils.rm_f(temp)
        end
        warn_mismatch(report, target) if report["result"] == "mismatch"
      end

      def warn_mismatch(report, target)
        first = report["differences"].first
        @diagnostics.warn("partial coverage shadow run: the partial map differs from the full map in " \
                          "#{report['total']} place(s), first #{first['kind']} #{first['name']}; this run used the " \
                          "full map. Report: #{shadow_clean(target)}")
      end

      def shadow_clean(value)
        plain_line(Text.utf8(value.to_s))
      end
    end
  end
end
