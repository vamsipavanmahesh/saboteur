# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Gets the heap ready at a fork boundary.
    #
    # Boot and candidate construction can leave garbage, fragmentation and
    # young objects in the heap. Forked children initially share its pages.
    # Later collection and object writes can make pages private. Preparing the
    # heap before a fork batch can reduce that copying. Call it once per phase
    # boundary, not per fork: preparing again while siblings are alive can
    # break sharing with those siblings.
    module ForkReadiness
      # Process.warmup (CRuby 3.3+) is made for this: a full collection that
      # also promotes survivors to the old generation and compacts. Without
      # it, a lone GC.compact still packs the heap (it runs a full collection
      # itself first) but does not promise old-generation promotion. Without
      # either, a full collection is the best that Ruby can do.
      def self.prepare_heap
        if Process.respond_to?(:warmup)
          Process.warmup
          return
        end

        if GC.respond_to?(:compact)
          GC.compact
          return
        end

        GC.start(full_mark: true, immediate_sweep: true)
        nil
      end
    end
  end
end
