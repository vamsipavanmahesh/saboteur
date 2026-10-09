# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # A snapshot of every process on the machine: { pid => Entry }.
    #
    # The supervisor reads it at least twice per mutant, so it must be cheap.
    # Spawning `ps` costs about 30 ms; reading the kernel directly costs a
    # few. Each backend gives the same facts:
    #
    #   ppid, pgid  to find descendants, even ones that left the group
    #   rss_kb      to cap memory (compare only values from one backend)
    #   zombie      exited but not yet reaped: nothing left to kill
    #   started     start time, so a recycled pid is never mistaken for one
    #               we saw earlier
    module ProcessTable
      Entry = Data.define(:pid, :ppid, :pgid, :rss_kb, :zombie, :started)

      def self.backends
        [Darwin, Linux, Ps].select(&:available?)
      end

      def self.backend
        @backend ||= backends.first
      end

      def self.snapshot
        backend.snapshot
      end

      # macOS: libproc, through Fiddle.
      module Darwin
        LISTALL_LIMIT = 16_384
        BSDINFO = 3
        TASKINFO = 4
        ZOMBIE = 5 # SZOMB in pbi_status
        # Byte offsets in struct proc_bsdinfo / proc_taskinfo (measured on
        # macOS 14, arm64; the layout is the same on x86_64).
        STATUS = 4
        PID = 12
        PPID = 16
        PGID = 100
        START_SECONDS = 120
        START_MICROS = 128
        RESIDENT = 8

        module_function

        def available?
          RUBY_PLATFORM.include?("darwin") && !functions.nil?
        end

        def snapshot
          list_all, info = functions
          pids = all_pids(list_all)
          bsd = Fiddle::Pointer.malloc(256, Fiddle::RUBY_FREE)
          task = Fiddle::Pointer.malloc(256, Fiddle::RUBY_FREE)
          pids.to_h { |pid| [pid, entry_for(pid, info, bsd, task) || exited(pid)] }
        end

        # libproc gives no details for a zombie (or a process that just
        # ended): it is listed but has nothing left to kill.
        def exited(pid)
          Entry.new(pid: pid, ppid: 0, pgid: 0, rss_kb: 0, zombie: true, started: nil)
        end

        def all_pids(list_all)
          buffer = Fiddle::Pointer.malloc(4 * LISTALL_LIMIT, Fiddle::RUBY_FREE)
          count = list_all.call(buffer, 4 * LISTALL_LIMIT)
          buffer[0, 4 * count].unpack("l*").reject(&:zero?)
        end

        def entry_for(pid, info, bsd, task)
          size = info.call(pid, BSDINFO, 0, bsd, 256)
          return nil if size < START_MICROS + 8

          raw = bsd[0, size]
          resident = info.call(pid, TASKINFO, 0, task, 256) >= RESIDENT + 8 ? task[RESIDENT, 8].unpack1("Q") : 0
          Entry.new(pid: pid, ppid: raw[PPID, 4].unpack1("L"), pgid: raw[PGID, 4].unpack1("L"),
                    rss_kb: resident / 1024, zombie: raw[STATUS, 4].unpack1("L") == ZOMBIE,
                    started: raw[START_SECONDS, 16].unpack("QQ"))
        end

        def functions
          return @functions if defined?(@functions)

          @functions = begin
            require "fiddle"
            library = Fiddle.dlopen("/usr/lib/libproc.dylib")
            [Fiddle::Function.new(library["proc_listallpids"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                                  Fiddle::TYPE_INT),
             Fiddle::Function.new(library["proc_pidinfo"],
                                  [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG,
                                   Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)]
          rescue LoadError, Fiddle::DLError
            nil
          end
        end
      end

      # Linux: /proc/<pid>/stat.
      module Linux
        PAGE_KB = 4

        module_function

        def available?
          File.exist?("/proc/self/stat")
        end

        def snapshot
          Dir.children("/proc").each_with_object({}) do |name, table|
            next unless name.match?(/\A\d+\z/)

            entry = entry_for(name.to_i)
            table[entry.pid] = entry if entry
          end
        end

        # Fields after the command name, which may itself hold spaces or ")".
        def entry_for(pid)
          stat = File.read("/proc/#{pid}/stat")
          fields = stat[(stat.rindex(")") + 2)..].split
          Entry.new(pid: pid, ppid: fields[1].to_i, pgid: fields[2].to_i, rss_kb: fields[21].to_i * page_kb,
                    zombie: fields[0] == "Z", started: fields[19].to_i)
        rescue SystemCallError
          nil
        end

        def page_kb
          @page_kb ||= begin
            require "etc"
            Etc.sysconf(Etc::SC_PAGESIZE) / 1024
          rescue StandardError
            PAGE_KB
          end
        end
      end

      # Anywhere else: one `ps` call. Slow (it spawns a process) but portable.
      module Ps
        COLUMNS = "pid=,ppid=,pgid=,rss=,stat=,lstart="

        module_function

        def available?
          true
        end

        def snapshot
          out = IO.popen(["ps", "-A", "-o", COLUMNS], err: File::NULL, &:read)
          out.each_line.with_object({}) do |line, table|
            pid, ppid, pgid, rss, state, *started = line.split
            next if started.empty?

            table[pid.to_i] = Entry.new(pid: pid.to_i, ppid: ppid.to_i, pgid: pgid.to_i, rss_kb: rss.to_i,
                                        zombie: state.start_with?("Z"), started: started.join(" "))
          end
        end
      end
    end
  end
end
