# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Records which Ruby methods were entered, by [first line, name] per file,
  # with a TracePoint on :call. Coverage's methods report does the same job
  # but its read walks every method in the process (about 8 ms per read once
  # an app is loaded), and the recorder reads twice per example. :call
  # events are rare next to :line events, and an endless def fires one too
  # (#107). Pass `files` (canonical paths) to keep only those; nil keeps all.
  class MethodCalls
    # The tracer the executable arms before the app loads; the engine reads
    # it once after boot and disables it.
    def self.boot
      @boot ||= new.enable
    end

    def self.booted
      @boot
    end

    def initialize(files = nil, canonical: ->(path) { path })
      @wanted = files && Hash.new { |hash, path| hash[path] = files.include?(canonical.call(path)) }
      @hits = new_hits
      @trace = TracePoint.new(:call) { |event| record(event) }
    end

    def enable
      @trace.enable unless @trace.enabled?
      self
    end

    def disable
      @trace.disable if @trace.enabled?
      self
    end

    # Stops recording without touching the TracePoint: toggling it costs
    # milliseconds once an app is loaded, so the recorder pauses per read.
    def pause
      @paused = true
      self
    end

    def resume
      @paused = false
      self
    end

    # file => Set of [line, name] since the last drain.
    def drain(clear: true)
      hits = @hits
      @hits = new_hits if clear
      hits
    end

    private

    def new_hits
      Hash.new { |hash, file| hash[file] = Set.new }
    end

    def record(event)
      # self.equal?(...) never sends a message to the traced receiver, which
      # may be a BasicObject proxy that answers every message (ActiveSupport's
      # deprecation proxies do).
      return if @paused || equal?(event.self)

      path = event.path
      return if @wanted && !@wanted[path]

      @hits[path] << [event.lineno, event.method_id]
    end
  end
end
