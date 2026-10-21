# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "shellwords"

module Saboteur
  module Reporter
    module Agent
      # The shell commands an agent is told to run next. Every word is escaped with
      # Shellwords, so a ref, path or subject holding shell syntax stays one literal
      # argument. A command for the agent protocol is never cut short: when it is
      # longer than MAX_BYTES it is left out, because half a command could run
      # something else. The text footer passes capped: false instead - there the
      # promise is the complete command, however long (#261).
      module Commands
        MAX_BYTES = 1024

        # Options typed on the command line that change how a run behaves.
        SETTING_FLAGS = { reeval: "--reeval", integration: "--integration", jobs: "--jobs",
                          timeout_factor: "--timeout-factor", json_report: "--json", html_report: "--html",
                          operators: "--operators", exclude_operators: "--exclude-operators",
                          baseline_passes: "--baseline-passes", max_duration: "--max-duration",
                          shard: "--shard" }.freeze

        # Not part of the selection a replay reproduces: a shard is a slice of
        # it, and a report path would overwrite the report the replay came
        # from (the audit preset names whole-project reports, #1185).
        REPLAY_SKIPPED = %i[shard json_report html_report].freeze

        # CLI-only boolean switches recorded in settings, mapped by value, so
        # an explicit false (--no-max-duration-ok over a config true) survives
        # into the generated commands instead of reverting to the config.
        BOOLEAN_SETTING_FLAGS = { allow_hazardous: { true => "--allow-hazardous" },
                                  allow_focus: { true => "--allow-focus" },
                                  max_duration_ok: { true => "--max-duration-ok",
                                                     false => "--no-max-duration-ok" } }.freeze

        class << self
          # Run the same selection again: ref, subjects, sources, tests, config,
          # cache mode and replay digest, with the recorded seed.
          def rerun(provenance)
            words = ["saboteur", "run", "--agent", *selection(provenance), "--seed", provenance.seed.to_s]
            finish(words, provenance)
          end

          # Replay one survivor by digest in the same selection. capped: false
          # skips the protocol byte cap, for callers that print to a terminal.
          def replay(provenance, digest, capped: true)
            words = ["saboteur", "run", "--id", digest, *selection(provenance, replay: true), "--seed",
                     provenance.seed.to_s]
            finish(words, provenance, capped: capped)
          end

          private

          def finish(words, provenance, capped: true)
            words += ["--", *provenance.sources] unless provenance.sources.empty?
            command = Shellwords.join(words)
            command if !capped || command.bytesize <= MAX_BYTES
          end

          def mode_words(provenance)
            words = []
            words << "--no-cache" if provenance.cache == false
            words << "--incremental" if provenance.incremental
            words.concat(boolean_words(provenance))
          end

          def boolean_words(provenance)
            BOOLEAN_SETTING_FLAGS.filter_map { |key, words| words[provenance.settings[key]] }
          end

          # An explicit scope is frozen as --test, which wins over inferred
          # selection by precedence, whatever the config file sets.
          def test_words(tests)
            tests.flat_map { |test| ["--test", test] }
          end

          # An empty list nobody typed came from the config file or its
          # default, which the command reads again, so its flag is left out
          # (#317). A typed empty list stays: it may clear a config value.
          def setting_words(provenance, replay: false)
            SETTING_FLAGS.flat_map do |key, flag|
              next [] if replay && REPLAY_SKIPPED.include?(key)
              next [] unless provenance.settings.key?(key)

              value = provenance.settings[key]
              next [] if value == [] && !provenance.typed_settings.include?(key)

              [flag, value.is_a?(Array) ? value.join(",") : value.to_s]
            end
          end

          # Whole-suite scope is a bare --all, only when no tests resolved;
          # --all never combines with --test.
          def selection(provenance, replay: false)
            words = []
            words.push("--config", provenance.config_path) if provenance.config_path
            words.push("--since", provenance.ref) if provenance.ref
            provenance.subjects.each { |subject| words.push("--subject", subject) }
            words << "--all" if provenance.settings[:all] && provenance.tests.empty?
            words.push(*test_words(provenance.tests))
            words.concat(setting_words(provenance, replay: replay))
            words.concat(mode_words(provenance))
            words.push("--id", provenance.digest) if provenance.digest && !replay
            words
          end
        end
      end
    end
  end
end
