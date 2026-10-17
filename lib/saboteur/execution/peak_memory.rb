# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Peak resident memory of a process from its proc status (#202). VmHWM is
    # the kernel's exact high-water mark, so no sampling interval can miss
    # it. Nil wherever procfs is absent (macOS), so reports omit the section
    # instead of printing a fake zero.
    module PeakMemory
      PROC_STATUS = "/proc/self/status"

      module_function

      # This process's peak RSS in MB, or nil when procfs is unavailable.
      def peak_mb(path = PROC_STATUS)
        rss_mb(File.read(path))
      rescue SystemCallError
        nil
      end

      def rss_mb(status)
        kb = status[/^VmHWM:\s*(\d+) kB/, 1]
        kb && (kb.to_i / 1024.0).round(1)
      end
    end
  end
end
