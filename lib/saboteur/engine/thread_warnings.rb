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
      # Well-known fork-time threads, with the condition each assurance
      # hangs on. Evidence: rails-mode children reconnect the database
      # (lib/saboteur/frameworks/rails.rb, after_fork); whether the debug
      # gem's console also attaches to forked children depends on its
      # fork_mode, whose default is :both, i.e. attach (RUBY_DEBUG_FORK_MODE;
      # ruby/debug's config.rb and SESSION.activate on_fork: true in
      # session.rb).
      REAPER = "AR Pool Reaper"

      KNOWN_FORK_THREADS = {
        REAPER => "ActiveRecord's connection-pool reaper: expected harmless when children " \
                  "reconnect the database after fork (rails mode does) - it only maintains " \
                  "the parent's pool",
        "DEBUGGER__::SESSION@server" => "the debug gem's remote-console server: what it does in " \
                                        "children depends on RUBY_DEBUG_FORK_MODE - with parent no " \
                                        "debugger runs in children; with child or both (the gem's " \
                                        "default) the debugger activates in children and can pause or " \
                                        "interfere with supervised mutation runs. For an unattended " \
                                        "run, do not start the remote debugger at all: drop " \
                                        "RUBY_DEBUG_OPEN or require \"debug\" without :open"
      }.freeze

      # In rails mode the children reconnect the database, so the pool
      # reaper is not worth a warning on every run (#1229).
      def self.warn(diagnostics, rails: false)
        others = Thread.list - [Thread.current]
        others = others.reject { |thread| thread.name == REAPER } if rails
        return if others.empty?

        unknown = false
        list = others.map do |thread|
          name = thread.name || thread.backtrace&.first || "unknown"
          explanation = KNOWN_FORK_THREADS[name]
          unknown = true unless explanation
          explanation ? "#{name} (#{explanation})" : name
        end.join(", ")
        message = "#{others.size} other thread(s) alive at fork time; they do not run in children: #{list}"
        if unknown
          message += "; a thread that does not run in a child cannot do background work a mutant's test may " \
                     "rely on (a pool reaper, a flusher), so results can differ when one is left behind"
        end
        diagnostics.warn(message)
      end
    end
  end
end
