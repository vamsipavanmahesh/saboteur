# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Threads do not survive fork, so a run names the ones alive when the
    # workers fork: by the name the owner gave the thread, else the first
    # frame of its backtrace, so the user can tell whether they matter (a
    # connection pool reaper, Sidekiq, an SDK's background flusher).
    # Known-harmless threads say so inline; an unknown thread gets the
    # generic caveat (#263).
    module ThreadWarnings
      # Well-known fork-time threads that cannot hurt the run.
      KNOWN_FORK_THREADS = {
        "AR Pool Reaper" => "ActiveRecord's connection-pool reaper: harmless - it only maintains the parent's " \
                            "pool; children reconnect the database after fork (rails mode)",
        "DEBUGGER__::SESSION@server" => "the debug gem's remote-console server: harmless for results - the " \
                                        "console just cannot attach to children; to not start it, drop " \
                                        "RUBY_DEBUG_OPEN or require \"debug\" without :open"
      }.freeze

      def self.warn(diagnostics)
        others = Thread.list - [Thread.current]
        return if others.empty?

        unknown = 0
        list = others.map do |thread|
          name = thread.name || thread.backtrace&.first || "unknown"
          explanation = KNOWN_FORK_THREADS[name]
          unknown += 1 unless explanation
          explanation ? "#{name} (#{explanation})" : name
        end.join(", ")
        message = "#{others.size} other thread(s) alive at fork time; they do not run in children: #{list}"
        if unknown.positive?
          message += "; a thread that does not run in a child cannot do background work a mutant's test may " \
                     "rely on (a pool reaper, a flusher), so results can differ when one is left behind"
        end
        diagnostics.warn(message)
      end
    end
  end
end
