# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "find"
require "pathname"
require "tmpdir"

module Saboteur
  module Execution
    # Runs mutants through a user-supplied shell command (#140): each
    # execution gets a FRESH disposable copy of the project tree, so every
    # mutant and every neutral check starts from a pristine snapshot and a
    # destructive command cannot poison later runs. The mutant is written
    # into the copy - never the real file; the runner's own writes never
    # follow symlinks and never leave the copy - and the command runs there
    # with the caller's permissions: unsandboxed, with network and side
    # effects exactly as if typed into a shell, including writing anywhere
    # it chooses by absolute path. Its exit status decides the verdict: 0
    # survived, non-zero killed (except the shell's 126/127 and signals,
    # which read as command/setup errors), deadline timeout. It is the mode
    # for target apps that cannot load inside this Ruby (apps on older
    # Rubies); it is explicitly slower, now also one tree copy per
    # execution.
    #
    # Safety shape, stated narrowly: the pristine reference is the real
    # tree itself, read per subject as subject.file_source; the copy is
    # not a canary and proves nothing by itself. Because only the copy is
    # mutated, a failed write or a command that keeps writing in the
    # background hits the copy, not the checkout; the command can still
    # write anywhere else by absolute path, so only trusted commands
    # belong here. The command's whole process group is TERM/KILLed and
    # reaped in an ensure on every exit path (verdict, timeout, error,
    # interrupt); a SIGKILL of this process can leave the group alive.
    # Output capture is bounded as it is written (a ring buffer), so a
    # chatty command cannot fill memory or disk. A neutral preflight runs
    # the command once on an untouched copy before any mutant exists, so a
    # typo command fails immediately with its own output.
    class ExternalRunner
      # The command is one test in the report's eyes: a kill names it as
      # the killer, a run lists it as executed.
      PSEUDO_TEST = "(test command)"

      # Shell "cannot execute" / "command not found" read as setup errors,
      # never as kills: the suite did not run.
      SETUP_EXIT_CODES = [126, 127].freeze

      # The child inherits this marker and Boot.refuse_recursion! refuses
      # any saboteur run inside it, so a test command that itself invokes
      # saboteur cannot mutate the copy mid-run.
      CHILD_MARKER = "SABOTEUR_EXTERNAL_CHILD"

      # Bundler env anchors a child command must never inherit (#435).
      BUNDLER_ANCHOR_KEYS = %w[
        BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION BUNDLE_APP_CONFIG
      ].freeze

      # with_unbundled_env deletes the whole BUNDLE_* prefix, which also
      # drops settings the SHELL exported - CI commonly exports
      # BUNDLE_PATH (plus resolution knobs) without writing .bundle/config,
      # and the child's bundler then cannot find the app's gems (#449).
      # Re-add these only when they came from the pre-bundler environment
      # (Bundler.original_env), never from bundler's own activation, and
      # never the anchor keys above.
      BUNDLER_PASSTHROUGH_KEYS = %w[
        BUNDLE_PATH BUNDLE_WITHOUT BUNDLE_WITH BUNDLE_FROZEN BUNDLE_DEPLOYMENT
      ].freeze

      # Bounded capture: only the last bytes of combined output are kept,
      # for preflight and error messages.
      OUTPUT_LIMIT = 64 * 1024

      # Grace for the capture drain after the command exits: a descendant
      # holding the pipe past this no longer blocks the run.
      DRAIN_GRACE = 0.5

      def initialize(command:, root:, path_sources: nil)
        @command = command
        # realpath, not expand_path: the tree must be judged by where it
        # really is, so a subject path can be checked against the same
        # canonical root without a symlink making it look outside (#305 QA).
        @root = File.realpath(root)
        # The Gemfile the command actually loads, root-relative: its own
        # pinned BUNDLE_GEMFILE when it sets one (Appraisal style), else
        # the root Gemfile (#644).
        pinned = pinned_gemfile
        @gemfile_name = pinned || "Gemfile"
        sources = path_sources || GemfilePathSources.resolve(@root, gemfile: pinned)
        @path_sources = classify_path_sources(sources)
        @copy_root = nil
        at_exit { close }
      rescue SystemCallError
        raise Error, "the test command root does not exist: #{root}"
      end

      # Runs the command once on an untouched copy before any mutant
      # exists. A failing command can never claim kills, so fail the whole
      # run here with the command's own output (#140, #305).
      # deadline is absolute (CLOCK_MONOTONIC): the copy is made first and
      # the command is admitted only with the time then remaining, so the
      # copy can never eat the budget while the command still gets its full
      # slice (#305 Architect). An already-spent deadline is a budget stop,
      # not a command failure - and so is a wait cut short with the overall
      # run budget also spent: the run is out of time, the command is not
      # at fault (#305 QA).
      # The budget only owns the outcome when it is the LIMITING deadline
      # (budget_deadline <= deadline): an own-slice timeout stays the
      # command's error even when the run budget is spent too, and the
      # cause is fixed at the moment of admission or timeout, before
      # TERM/KILL and the drain can cross the budget and relabel it (#305
      # Principal).
      def preflight!(deadline:, budget_deadline: nil)
        budget_limited = !budget_deadline.nil? && budget_deadline <= deadline
        result = with_fresh_copy do
          remaining = deadline - monotonic
          if remaining <= 0
            raise BudgetPhaseTimeout, "the --max-duration budget stopped the external preflight" if budget_limited

            raise Error, "the test command's preflight deadline was spent before the command could start"
          end

          spawn_and_wait(remaining, timeout_cause: budget_limited ? :budget : :own, budget_deadline: budget_deadline)
        end
        if result == :budget_timeout
          raise BudgetPhaseTimeout, "the --max-duration budget stopped the external preflight"
        end

        case result
        when 0 then true
        when Exception
          raise Error, "the test command could not be started: #{result.message}"
        else
          raise Error, "the test command fails on the unchanged tree " \
                       "(#{describe_exit(result)}):\n#{last_output}"
        end
      end

      # Mutation-visibility check (#441): the command must FAIL with the
      # subject file replaced by a load-time error. A pass means the
      # command never sees the copy's file - a RUBYLIB/-I path or an
      # installed gem anchors it to the real tree, or the suite never
      # loads the file - and every mutant on it "survives" unseen, so the
      # score would read 0.0 % for nothing. Warn loudly and let the run
      # continue: the file may legitimately be uncovered. The first
      # runnable subject stands for the whole scope: anchoring breaks
      # every file alike. Returns the warning, or nil when the command
      # saw the broken file. Budget and deadline faults still raise.
      def visibility_check(subject:, deadline:, budget_deadline: nil)
        budget_limited = !budget_deadline.nil? && budget_deadline <= deadline
        result = with_fresh_copy do
          remaining = deadline - monotonic
          if remaining <= 0
            if budget_limited
              raise BudgetPhaseTimeout,
                    "the --max-duration budget stopped the mutation visibility check"
            end

            raise Error, "the mutation visibility check's deadline was spent before the command could start"
          end

          write_subject(subject, visibility_mutation(subject))
          spawn_and_wait(remaining, timeout_cause: budget_limited ? :budget : :own,
                                    budget_deadline: budget_deadline)
        end
        if result == :budget_timeout
          raise BudgetPhaseTimeout,
                "the --max-duration budget stopped the mutation visibility check"
        end

        visibility_warning(subject, result)
      end

      # Same contract as Runner#run. text, test_ids and eval_prefix belong
      # to the in-process machinery and are ignored here. The neutral run
      # (mutation nil) writes the unchanged bytes explicitly: every
      # execution proves the write path against pristine content (#305).
      def run(subject:, text:, test_ids:, timeout:, mutation: nil, eval_prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
        started = monotonic
        message = nil
        status = begin
          with_fresh_copy do
            write_subject(subject, mutation)
            verdict_for(spawn_and_wait(timeout))
          end
        # A copy or write failure is this execution's outcome, never a crash
        # of the run: report it with bounded context like any command error
        # (#305 QA).
        rescue Error, SystemCallError => e
          message = bounded(e.message)
          :error
        end
        Runner::Outcome.new(status: status, runtime: monotonic - started,
                            failed_ids: status == :killed ? [PSEUDO_TEST] : [],
                            executed_ids: status == :error ? [] : [PSEUDO_TEST],
                            message: message || (status == :error ? error_context : nil))
      end

      # Drops the current disposable copy. Public so the engine can release
      # the tree as soon as the run ends; idempotent, and the at_exit
      # backstop calls it again.
      def close
        FileUtils.rm_rf(@copy_root) if @copy_root
        @copy_root = nil
      rescue SystemCallError
        nil
      end

      private

      # A pristine copy of the tree for one execution (#305 QA/DevRel): the
      # previous execution's copy - mutated file, command side effects and
      # all - is dropped before the new one is made.
      def with_fresh_copy
        close
        # realpath the copy root too: macOS tmp dirs are /var symlinked to
        # /private/var, and the containment check compares canonical link
        # targets against this root - both sides must be canonical (#305).
        @copy_root = File.realpath(Dir.mktmpdir("saboteur-external-"))
        FileUtils.cp_r(File.join(@root, "."), @copy_root, preserve: true)
        rebuild_symlinks
        rebase_path_sources
        yield
      end

      # path: sources are judged against the canonical root (#644): a
      # RELATIVE source resolving outside the tree would escape the
      # disposable copy, so it refuses the run at startup naming the
      # source; an ABSOLUTE source pointing into the original tree is
      # rebased into the copy below so bundler loads the copy's (possibly
      # mutated) code, never the original's. Anything unresolved or
      # ambiguous refuses - never a guess that could load unmutated code.
      def classify_path_sources(sources)
        sources.each_with_object(rebase: []) do |src, groups|
          expanded = GemfilePathSources.canonical_path(src.expanded)
          # The root itself counts as inside: a `gemspec` line makes
          # Bundler report the gem's own path source ".", expanded to the
          # project root - refusing it would refuse every gem-style
          # project (#644 security).
          inside = expanded == @root || expanded.start_with?("#{@root}/")
          next if inside && !Pathname.new(src.original).absolute?
          next if !inside && Pathname.new(src.original).absolute?

          unless inside
            raise ConfigError, "the Gemfile's path: source \"#{src.name}\" (#{src.original}) resolves outside the " \
                               "project root (#{expanded}); external test commands need a self-contained tree"
          end

          groups[:rebase] << [src, expanded]
        end
      end

      # Rewrites each rebased source in the COPY's Gemfile (quoted option)
      # and Gemfile.lock (PATH remote line). Zero or several matches mean
      # the file computes the path or disagrees with Bundler's resolution -
      # refuse rather than risk loading the original tree (#644).
      def rebase_path_sources
        @path_sources[:rebase].each do |src, expanded|
          copy_path = expanded == @root ? @copy_root : File.join(@copy_root, expanded.delete_prefix("#{@root}/"))
          rewrite_gemfile_source(src, copy_path)
          rewrite_lockfile_source(src, copy_path)
        end
      end

      def rewrite_gemfile_source(src, copy_path)
        path = File.join(@copy_root, @gemfile_name)
        text = File.read(path)
        pattern = /(path:\s*["'])#{Regexp.escape(src.original)}(["'])/
        raise ConfigError, ambiguous_source_message(src) unless text.scan(pattern).size == 1

        File.write(path, text.sub(pattern) { "#{Regexp.last_match(1)}#{copy_path}#{Regexp.last_match(2)}" })
      end

      def rewrite_lockfile_source(src, copy_path)
        # Bundler names the lockfile after the Gemfile: <gemfile>.lock.
        path = File.join(@copy_root, "#{@gemfile_name}.lock")
        return unless File.file?(path)

        text = File.read(path)
        pattern = /^(\s*remote: )#{Regexp.escape(src.original)}$/
        File.write(path, text.sub(pattern) { "#{Regexp.last_match(1)}#{copy_path}" }) if text.scan(pattern).size == 1
      end

      def ambiguous_source_message(src)
        "could not rebase the Gemfile's path: source \"#{src.name}\" (#{src.original}) into the disposable copy; " \
          "external test commands need a literal path: option they can rewrite"
      end

      # A command-pinned Gemfile must live inside the tree, or the copy
      # would read a Gemfile - and its path: sources - from outside (#644).
      # Returns its root-relative path, or nil for the root Gemfile.
      def pinned_gemfile
        pinned = GemfilePathSources.pinned_in(@command)
        return nil unless pinned

        expanded = GemfilePathSources.canonical_path(File.expand_path(pinned, @root))
        unless expanded == @root || expanded.start_with?("#{@root}/")
          raise ConfigError, "the test command pins BUNDLE_GEMFILE (#{pinned}) outside the project root " \
                             "(#{expanded}); external test commands need the Gemfile inside the tree"
        end

        expanded.delete_prefix("#{@root}/")
      end

      # cp_r keeps symlinks, and a write through a link that escapes the
      # copy would land in the real tree. Links resolving inside the tree
      # are REBUILT as relative links inside the copy: alias identity is
      # preserved, so requiring the alias sees the same (possibly mutated)
      # content as the real path, and the link can never point out (#305
      # QA). Chains collapse to the final target, which is equivalent.
      # Anything escaping the tree or unresolvable refuses the run.
      def rebuild_symlinks
        Find.find(@copy_root) do |path|
          next unless File.symlink?(path)

          target = File.realpath(path)
          unless target.start_with?("#{@copy_root}/")
            raise Error, "the tree links outside itself: #{path.sub("#{@copy_root}/", '')} -> #{target}; " \
                         "external test commands need a self-contained tree"
          end

          relative = Pathname.new(target).relative_path_from(Pathname.new(File.dirname(path))).to_s
          File.unlink(path)
          File.symlink(relative, path)
        rescue SystemCallError
          raise Error, "unresolvable symlink in the tree: #{path.sub("#{@copy_root}/", '')}"
        end
      end

      # The mutation's edits apply at absolute byte offsets in the file;
      # the neutral run writes the original bytes back. The reference text
      # is the real tree's, never the copy's (#305 DevRel canary).
      def write_subject(subject, mutation)
        path = File.join(@copy_root, relative(subject))
        File.binwrite(path, mutation ? mutated_source(subject, mutation) : subject.file_source)
      end

      # The subject must live under the canonical root; anything else -
      # absolute or `..` traversal - is refused, never joined onto the copy
      # (#305 QA).
      def relative(subject)
        # realpath like the root: macOS tmp is /var symlinked to /private/var,
        # so a spelled subject path must canonicalize before the containment
        # check or every run is refused as outside the root (#442).
        expanded = File.realpath(subject.file)
        prefix = "#{@root}/"
        raise Error, "the subject file is outside the project root: #{subject.file}" unless expanded.start_with?(prefix)

        expanded[prefix.length..]
      end

      def mutated_source(subject, mutation)
        source = subject.file_source.dup.b
        mutation.edits.sort_by(&:start_byte).reverse_each do |edit|
          source = source.byteslice(0, edit.start_byte) + edit.replacement.b + source.byteslice(edit.end_byte..)
        end
        source.force_encoding(Encoding::UTF_8)
      end

      def verdict_for(result)
        case result
        when :timeout then :timeout
        when Exception, :signal, *SETUP_EXIT_CODES then :error
        when 0 then :survived
        else :killed
        end
      end

      def error_context
        "#{describe_exit(@last_result)}: #{last_output}"
      end

      # timeout_cause fixes who owns a timeout at the moment the wait ends,
      # BEFORE the ensure's TERM/KILL grace and capture drain run: that
      # cleanup can cross the run budget, and a budget crossed there must
      # not relabel the command's own timeout as a budget stop (#305
      # Principal). :budget_timeout is decided here, never after.
      def spawn_and_wait(timeout, timeout_cause: :own, budget_deadline: nil)
        # Always through the shell: users write pipelines and redirects,
        # and a bare unknown word must exit 127 instead of raising ENOENT.
        start_capture
        pid = spawn_shell
        # The parent's copy of the write end closes right after the spawn:
        # while it stays open the reader never sees EOF and the drain below
        # would always wait out its grace (#305 Architect).
        @capture_writer.close
        @capture_writer = nil
        @last_result = await_exit(pid, timeout)
        if @last_result == :timeout && timeout_cause == :budget && budget_deadline && monotonic >= budget_deadline
          @last_result = :budget_timeout
        end
        @last_result
      rescue SystemCallError => e
        @last_result = e
      ensure
        # The whole process group goes down on every exit path - verdict,
        # timeout, error and interrupt alike - so background descendants
        # cannot write after the verdict is in (#305).
        reap_tree(pid) if pid
        finish_capture
      end

      def spawn_shell
        Process.spawn(child_env, ["/bin/sh", "sh"], "-c", @command, chdir: @copy_root,
                                                                    pgroup: true,
                                                                    out: @capture_writer,
                                                                    err: @capture_writer,
                                                                    unsetenv_others: true)
      end

      # A `bundle exec saboteur` parent - or a shell with BUNDLE_GEMFILE
      # exported - anchors the child command's bundler to the REAL tree:
      # the child resolves the project gem from the unmutated checkout, the
      # mutant is never exercised and every mutant survives (#435). The
      # copy carries its own Gemfile, so the child's bundler must resolve
      # from @copy_root instead: hand the child the unbundled environment
      # and drop the anchor keys outright (they can also sit in Bundler's
      # ORIGINAL_ENV and survive with_unbundled_env). RUBYOPT/RUBYLIB keep
      # their non-bundler parts; everything else passes through unchanged.
      def child_env
        env = defined?(Bundler) ? Bundler.with_unbundled_env { ENV.to_h } : ENV.to_h
        BUNDLER_ANCHOR_KEYS.each { |key| env.delete(key) }
        if defined?(Bundler)
          original = Bundler.original_env
          BUNDLER_PASSTHROUGH_KEYS.each { |key| env[key] = original[key] if original.key?(key) }
          restore_dropped_rubylib_entries(env, original)
        end
        if (rubyopt = env["RUBYOPT"])
          rubyopt = rubyopt.gsub(%r{\s*-rbundler/setup}, "").strip
          rubyopt.empty? ? env.delete("RUBYOPT") : env["RUBYOPT"] = rubyopt
        end
        env.merge(CHILD_MARKER => "1")
      end

      # bundler <=2.5 scrubs even shell-exported entries (verified
      # 2.5.22); bundler >=2.6.0 restores the pre-bundler value wholesale
      # (verified 2.6.0/2.6.9), where this restore is a no-op. A
      # relocated/toolcache Ruby needs that entry to find its stdlib
      # (#584). Rebuild the list from the pre-bundler one - RUBYLIB is
      # ordered, and two directories providing the same feature load in
      # path order - then append entries only the scrubbed list has;
      # bundler's own additions (absent from the pre-bundler value) stay
      # dropped, and duplicates collapse to first occurrence.
      def restore_dropped_rubylib_entries(env, original)
        before = original["RUBYLIB"].to_s.split(File::PATH_SEPARATOR)
        return if before.empty?

        after = env["RUBYLIB"].to_s.split(File::PATH_SEPARATOR)
        env["RUBYLIB"] = (before | after).join(File::PATH_SEPARATOR)
      end

      # Only a failing exit proves the command saw the broken file; a
      # pass is the anchoring or no-coverage case, and a timeout or setup
      # failure leaves visibility unknown. Both warn and name the file.
      def visibility_warning(subject, result)
        return nil if result.is_a?(Integer) && !result.zero? && !SETUP_EXIT_CODES.include?(result)

        detail = case result
                 when 0 then "the test command still passed"
                 when :timeout then "the test command timed out"
                 when :signal, *SETUP_EXIT_CODES then "the test command could not run (#{describe_exit(result)})"
                 when Exception then "the test command could not be started: #{result.message}"
                 end
        "mutation visibility check failed for #{relative(subject)}: #{detail} with the file replaced by a " \
          "load-time error, so mutants in it may all survive unseen and the score would read 0.0 %. The " \
          "command must load the project's code from the mutated copy; check for anchors to the real tree " \
          "(RUBYLIB, -I paths, an installed gem) or narrow the scope to files the suite loads."
      end

      # The whole file becomes a load-time error: any load of it from the
      # copy fails the suite, while a command anchored elsewhere is
      # untouched. Valid syntax, so only an actual load trips it.
      def visibility_mutation(subject)
        source = subject.file_source
        edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: 0, end_byte: source.bytesize,
                                                  replacement: 'raise "saboteur mutation visibility check: ' \
                                                               'this file must not load during the check"')
        Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "visibility_check", edits: [edit],
                                               coarse: false)
      end

      def await_exit(pid, timeout)
        deadline = monotonic + timeout
        loop do
          done, status = Process.wait2(pid, Process::WNOHANG)
          return status.exitstatus || :signal if done
          return :timeout if monotonic >= deadline

          sleep 0.01
        end
      end

      def reap_tree(pid)
        return unless tree_alive?(pid)

        Process.kill("TERM", -pid)
        deadline = monotonic + 2
        sleep 0.02 while monotonic < deadline && tree_alive?(pid)
        Process.kill("KILL", -pid) if tree_alive?(pid)
        Process.wait2(pid)
      rescue SystemCallError
        nil
      end

      def tree_alive?(pid)
        Process.kill(0, -pid)
        true
      rescue SystemCallError
        false
      end

      # A ring buffer on a pipe: output is bounded as it is written, never
      # spooled to disk (Principal, #305). The buffer lives outside the
      # thread so a bounded drain still keeps what was captured.
      def start_capture
        @capture_reader, @capture_writer = IO.pipe
        @capture_buffer = +""
        @capture_thread = Thread.new do
          loop do
            @capture_buffer << @capture_reader.readpartial(16_384)
            if @capture_buffer.bytesize > OUTPUT_LIMIT
              @capture_buffer = @capture_buffer.byteslice(-OUTPUT_LIMIT, OUTPUT_LIMIT)
            end
          end
        rescue IOError # EOFError included: the command closed its output
          nil
        end
      end

      # The command is done, but a descendant that escaped the process
      # group (setsid/daemon) can hold the write end open forever, so the
      # drain is bounded: the reader gets a short grace to see EOF, then it
      # is killed and its captured bytes kept. Escaped sessions are not
      # contained - they only cannot block the run or leak the fd (#305
      # Architect). Both parent ends are always closed.
      def finish_capture
        @capture_writer&.close
        if @capture_thread
          @capture_thread.join(DRAIN_GRACE) || @capture_thread.kill
          @capture_thread.join
        end
        @capture_reader&.close
        @captured = @capture_buffer
        @capture_reader = @capture_writer = @capture_thread = @capture_buffer = nil
      end

      # Captured bytes become report JSON: force UTF-8 and drop invalid
      # sequences - the ring buffer can start mid-multibyte after a
      # truncation (#305 Principal).
      def last_output
        bounded(@captured.to_s).strip.then { |text| text.empty? ? "(no output)" : text }
      end

      def bounded(text)
        text.dup.force_encoding(Encoding::UTF_8).scrub("")[0, OUTPUT_LIMIT]
      end

      def describe_exit(result)
        if SETUP_EXIT_CODES.include?(result)
          "exit #{result} - the shell could not run the command"
        elsif result == :signal
          "killed by a signal"
        elsif result == :timeout
          "timed out"
        elsif result.is_a?(Exception)
          "could not start: #{result.message}"
        else
          "exit #{result}"
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
