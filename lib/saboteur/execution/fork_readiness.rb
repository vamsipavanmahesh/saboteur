# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Gets the heap ready at a fork boundary.
    #
    # A booted target leaves the heap fragmented and entirely young. Every
    # process forked from it starts with a copy, and the garbage collector
    # then rewrites young objects in each child, turning shared pages into
    # private ones. Preparing at the boundary - after boot and candidate
    # construction, before the coverage child and before the worker batch -
    # packs the live objects into fewer pages so children share them instead
    # of copying them. Call it once per phase boundary, never per fork:
    # compacting again after sibling processes exist costs a full collection
    # per fork and cannot undo the copies they already made.
    module ForkReadiness
      # Process.warmup (CRuby 3.3+) is made for this: a full collection that
      # also promotes survivors to the old generation and compacts. Without
      # it, a lone GC.compact still packs the heap (it runs a full collection
      # itself first) but does not promise old-generation promotion. Without
      # either, a full collection is the best that Ruby can do.
      def self.prepare_heap
        if Process.respond_to?(:warmup)
          Process.warmup
        elsif GC.respond_to?(:compact)
          GC.compact
        else
          GC.start(full_mark: true, immediate_sweep: true)
        end
        nil
      end
    end
  end
end
