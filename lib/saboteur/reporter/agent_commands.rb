# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "shellwords"

module Saboteur
  module Reporter
    module Agent
      # The shell commands an agent is told to run next. Every word is escaped with
      # Shellwords, so a ref, path or subject holding shell syntax stays one literal
      # argument. A command is never cut short: when it is longer than MAX_BYTES it
      # is left out, because half a command could run something else.
      module Commands
        MAX_BYTES = 1024

        # Options typed on the command line that change how a run behaves.
        SETTING_FLAGS = { reeval: "--reeval", integration: "--integration", jobs: "--jobs",
                          timeout_factor: "--timeout-factor", json_report: "--json", html_report: "--html" }.freeze

        class << self
          # Run the same selection again: ref, subjects, sources, tests, config,
          # cache mode and replay digest, with the recorded seed.
          def rerun(provenance)
            words = ["saboteur", "run", "--agent", *selection(provenance), "--seed", provenance.seed.to_s]
            finish(words, provenance)
          end

          # Replay one survivor by digest in the same selection.
          def replay(provenance, digest)
            words = ["saboteur", "run", "--id", digest, *selection(provenance, replay: true), "--seed",
                     provenance.seed.to_s]
            finish(words, provenance)
          end

          private

          def finish(words, provenance)
            words += ["--", *provenance.sources] unless provenance.sources.empty?
            command = Shellwords.join(words)
            command.bytesize <= MAX_BYTES ? command : nil
          end

          def selection(provenance, replay: false)
            words = []
            words.push("--config", provenance.config_path) if provenance.config_path
            words.push("--since", provenance.ref) if provenance.ref
            provenance.subjects.each { |subject| words.push("--subject", subject) }
            provenance.tests.each { |test| words.push("--test", test) }
            SETTING_FLAGS.each do |key, flag|
              words.push(flag, provenance.settings[key].to_s) if provenance.settings.key?(key)
            end
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
