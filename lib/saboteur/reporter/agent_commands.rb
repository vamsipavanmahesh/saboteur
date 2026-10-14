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
                          operators: "--operators", exclude_operators: "--exclude-operators" }.freeze

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

          # An explicit scope is frozen as --test, which wins over inferred
          # selection by precedence, whatever the config file sets.
          def test_words(tests)
            tests.flat_map { |test| ["--test", test] }
          end

          def setting_words(provenance)
            SETTING_FLAGS.flat_map do |key, flag|
              next [] unless provenance.settings.key?(key)

              value = provenance.settings[key]
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
            words.concat(setting_words(provenance))
            words << "--no-cache" if provenance.cache == false
            words << "--incremental" if provenance.incremental
            words.push("--id", provenance.digest) if provenance.digest && !replay
            words
          end
        end
      end
    end
  end
end
