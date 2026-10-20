# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Records which lines ran, per file, with a TracePoint on :line (#725). A
  # per-test recorder can drain it between tests instead of calling
  # Coverage.result, whose read walks every file of the process. Pass `files`
  # (canonical paths) to keep only those; nil keeps all. Not wired into the
  # recorder yet: it matches Coverage's lines mode on saboteur's own suite
  # line for line, but has no branches, so the recorder's branch data still
  # needs its own design.
  class LineHits
    def initialize(files = nil, canonical: ->(path) { path })
      @wanted = files && Hash.new { |hash, path| hash[path] = wanted?(files, canonical, path) }
      @hits = new_hits
      @trace = TracePoint.new(:line, &method(:record))
    end

    def enable
      @trace.enable
      self
    end

    def disable
      @trace.disable
      self
    end

    # Stops recording without touching the TracePoint: toggling it costs
    # milliseconds once an app is loaded, so a recorder pauses around its own
    # work instead.
    def pause
      @paused = true
      self
    end

    def resume
      @paused = false
      self
    end

    # file => Set of line numbers since the last drain. A failure inside the
    # tracer is raised here: raising inside the TracePoint would unwind the
    # program being traced.
    def drain(clear: true)
      failure = @failure
      @failure = nil
      raise failure if failure

      hits = @hits
      @hits = new_hits if clear
      hits
    end

    private

    def new_hits
      Hash.new { |hash, file| hash[file] = Set.new }
    end

    # A path the canonicalizer refuses is not a wanted file: a NUL byte in an
    # eval'd file name raises ArgumentError, and a name that is not a file
    # ("(eval at ...)") raises ENOENT from a realpath canonicalizer.
    def wanted?(files, canonical, path)
      files.include?(canonical.call(path))
    rescue ArgumentError, SystemCallError, TypeError
      false
    end

    def record(event)
      return if @paused

      path = event.path
      return if @wanted && !@wanted[path]

      @hits[path] << event.lineno
    rescue StandardError => e
      @failure ||= e
    end
  end
end
