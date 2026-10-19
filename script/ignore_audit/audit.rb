# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "stringio"

require_relative "../../lib/saboteur"

# Ignore-hygiene audit (#703). A digest a PR ADDS to
# config/saboteur_ignore.rb must arise live: a real mutant on the PR head
# produces it. A digest a PR DROPS must be dead (no mutant produces it any
# more) or still run and be killed by the suite. The #571 incident dropped
# an entry whose mutant was still live; scoped dogfood could not see it
# because the subject had not changed.
module IgnoreAudit
  IGNORE_FILE = "config/saboteur_ignore.rb"
  CONFIG_FILE = "config/saboteur.rb"

  class Error < StandardError; end

  # The audit could not see everything it needs (unparseable ignore file,
  # config changed mid-range). Maps to exit 3: never a clean run.
  class Incomplete < Error; end

  Violation = Data.define(:entry, :problem)

  # Static reader for the ignore file (security review): the head's
  # config/saboteur_ignore.rb is pull-request code, so it must never
  # execute in the audit - IgnoreList.load is Kernel.load, and a single
  # `exit 0` line would make any churn read clean. Prism reads the DSL
  # instead, accepting ONLY literal entries:
  #
  #   Saboteur.ignore do |i|
  #     i.mutation "<digest>", subject: "<subject>", reason: "<reason>", state: "<state>"
  #   end
  #
  # Adjacent string literals ("a" "b") are still literals. Anything else -
  # interpolation, variables, extra calls, assignments, a missing reason -
  # means the audit cannot see the entries and raises Incomplete.
  class StaticEntries
    class << self
      def parse(source)
        result = Prism.parse(source)
        raise Incomplete, "#{IGNORE_FILE} does not parse" unless result.success?

        ignore_blocks(result.value).flat_map { |block| entries_from(block) }
      end

      private

      # Every top-level statement must be a Saboteur.ignore block (the repo
      # groups entries under more than one); any other code is Incomplete.
      def ignore_blocks(program)
        statements = program.statements&.body || []
        raise Incomplete, "#{IGNORE_FILE} holds no Saboteur.ignore block" if statements.empty?
        unless statements.all? { |statement| ignore_call?(statement) }
          raise Incomplete, "#{IGNORE_FILE} must hold only Saboteur.ignore blocks, nothing else"
        end

        statements.map(&:block)
      end

      def ignore_call?(node)
        node.is_a?(Prism::CallNode) && node.name == :ignore && node.arguments.nil? &&
          node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Saboteur &&
          node.block.is_a?(Prism::BlockNode)
      end

      def entries_from(block)
        parameters = block.parameters&.parameters
        param = parameters&.requireds&.first
        (block.body&.body || []).map { |statement| entry_from(statement, param) }
      end

      def entry_from(statement, param)
        unless mutation_call?(statement, param)
          raise Incomplete, "#{IGNORE_FILE} holds more than i.mutation entries: #{statement.slice[0, 40].inspect}..."
        end

        digest, values = entry_values(statement)
        unknown = values.keys - %i[subject reason state]
        raise Incomplete, "#{IGNORE_FILE} entry has non-literal or unknown arguments" if digest.nil? || unknown.any?

        missing = %i[subject reason].reject { |key| values[key] }
        raise Incomplete, "#{IGNORE_FILE} entry is missing #{missing.join(', ')}" if missing.any?

        Saboteur::IgnoreList::Entry.new(subject: values[:subject], mutation: digest,
                                        reason: values[:reason],
                                        state: values[:state] || "accepted_equivalent")
      end

      def mutation_call?(statement, param)
        statement.is_a?(Prism::CallNode) && statement.name == :mutation && statement.block.nil? &&
          param && statement.receiver.is_a?(Prism::LocalVariableReadNode) &&
          statement.receiver.name == param.name
      end

      def entry_values(call)
        arguments = call.arguments&.arguments || []
        keywords = arguments.last.is_a?(Prism::KeywordHashNode) ? arguments.pop.elements : []
        unless arguments.size <= 1 && keywords.all?(Prism::AssocNode)
          raise Incomplete, "#{IGNORE_FILE} entry takes one digest plus literal keywords"
        end

        values = keywords.to_h { |element| [element.key.unescaped.to_sym, literal(element.value)] }
        [literal(arguments.first), values]
      end

      # A plain string, or adjacent literals ("a" "b") Prism parses as an
      # InterpolatedStringNode of StringNode parts. Interpolation with
      # non-literal parts (embedded code) is NOT a literal: nil.
      def literal(node)
        case node
        when Prism::StringNode then node.unescaped
        when Prism::InterpolatedStringNode
          node.parts.all?(Prism::StringNode) ? node.parts.map(&:unescaped).join : nil
        end
      end
    end
  end

  # The git surface, injectable for specs.
  class Git
    def initialize(dir: Dir.pwd)
      @dir = dir
    end

    def changed?(base, head, path = IGNORE_FILE)
      out, status = Open3.capture2("git", "-C", @dir, "diff", "--name-only", "#{base}..#{head}", "--", path)
      raise Error, "git diff #{base}..#{head} failed" unless status.success?

      !out.strip.empty?
    end

    def entries_at(ref)
      out, status = Open3.capture2("git", "-C", @dir, "show", "#{ref}:#{IGNORE_FILE}")
      return [] unless status.success? # no ignore file at this ref yet

      StaticEntries.parse(out)
    end
  end

  # Digest resolution against the audited tree with the project's OWN
  # config (config/saboteur.rb): the include set and the mutation-source
  # settings decide which digests arise, so digests compare equal with the
  # dogfood run. In CI this code runs from the BASE ref's checkout, so the
  # digests are generated by the BASE ref's operators against the HEAD
  # tree's sources. Two deliberate asymmetries with a normal run:
  #
  # * Config::DEFAULTS are never consulted: their excludes hide names like
  #   lib/**/test_*.rb that this project mutates, which let a live digest
  #   read as dead (the f2ba2275de6bc416 bypass).
  # * The run's exclude list is not applied either: an ignore entry
  #   outlives exclude edits, so liveness asks "would this mutant still be
  #   generated from the subject's current source", not "is the subject in
  #   the current run scope".
  class Resolver
    def initialize(root:)
      config = Saboteur::Config.load(root: root)
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      hazard = Saboteur::MutationSource::HazardGuard.new(config["hazard"])
      @candidates = Saboteur::Engine::Candidates.build(config, diagnostics, hazard_guard: hazard)
      finder = Saboteur::SubjectFinder.new
      files = config["include"].flat_map { |pattern| Dir[File.join(root, pattern)] }.uniq
      @subjects_by_id = files.flat_map { |file| finder.call(file).subjects }.group_by(&:id)
    end

    # True when a real mutant of the entry's own subject produces the
    # entry's digest on this tree - the exact [subject, digest] binding
    # IgnoreList looks up.
    def live?(entry)
      (@subjects_by_id[entry.subject] || []).any? do |subject|
        @candidates.for(subject).any? do |mutation, _text|
          mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source) ==
            entry.mutation
        end
      end
    end
  end

  # Kill proof for a dropped-but-live digest: the mutant runs against the
  # suite through the normal replay path; exit 0 means it is killed (or
  # filtered as equivalent), anything else means it still survives.
  #
  # A drop whose subject sits under the project config's exclude list can
  # NEVER pass this proof: --subject matches no subject, the replay exits
  # 2, and the audit reads that as not-killed. Rework the exclusion or
  # kill the mutant in source before dropping such an entry.
  #
  # Time budget: every dropped-but-live digest costs a full suite replay
  # (baseline checks plus the mutant run). That is why only this path
  # shells out - no-churn and added-digest audits never start a replay -
  # and why a drop-heavy change makes this the slowest job in the
  # workflow.
  class KillProof
    def initialize(root: Dir.pwd, spec: nil, exe: "exe/saboteur")
      @root = root
      @spec = spec
      @exe = exe
    end

    def killed?(entry)
      system("bundle", "exec", @exe, "run", "--id", entry.mutation,
             "--subject", entry.subject, "--test", spec, chdir: @root)
    end

    private

    # The project's own spec target when its config names one (this repo
    # runs spec/saboteur; its e2e specs spawn saboteur subprocesses and
    # would recurse); a bare spec/ otherwise. Loaded lazily so a no-churn
    # run never touches the config.
    def spec
      @spec ||= begin
        args = Saboteur::Config.load(root: @root)["rspec_args"]
        args.grep_v(/\A-/).first || "spec"
      end
    end
  end

  # The churn rule itself. Exit 0: clean or untouched. 1: violations.
  # 3: incomplete - the audit could not see everything (unparseable ignore
  # file, config changed in the range); never reads as clean.
  class Audit
    def initialize(base:, head:, git: Git.new, out: $stdout, resolver: nil, kill_proof: nil)
      @base = base
      @head = head
      @git = git
      @out = out
      @resolver = resolver
      @kill_proof = kill_proof || KillProof.new
    end

    def call
      unless @git.changed?(@base, @head)
        @out.puts "ignore-audit: #{IGNORE_FILE} unchanged in #{@base}..#{@head}; nothing to audit"
        return 0
      end

      # The resolver reads ONE config; a range that also edits
      # config/saboteur.rb (a PR could set include = [] and make every
      # drop read dead) is for a human: incomplete, never clean.
      if @git.changed?(@base, @head, CONFIG_FILE)
        @out.puts "ignore-audit: #{CONFIG_FILE} changed in #{@base}..#{@head}; audit is incomplete"
        return 3
      end

      added, dropped = churn
      violations = []
      added.each do |entry|
        violations << Violation.new(entry, "added digest is not live") unless resolver.live?(entry)
      end
      dropped.each do |entry|
        next unless resolver.live?(entry)
        next if @kill_proof.killed?(entry)

        violations << Violation.new(entry, "dropped digest is still live and the suite does not kill it")
      end
      report(added, dropped, violations)
      violations.empty? ? 0 : 1
    rescue Incomplete => e
      @out.puts "ignore-audit: incomplete: #{e.message}"
      3
    end

    private

    # Built only on churn: the common no-change CI run stays instant.
    def resolver
      @resolver ||= Resolver.new(root: Dir.pwd)
    end

    # Churn compares [subject, digest] pairs: moving one digest to a
    # different subject is an add plus a drop, and editing only an entry's
    # reason or state is not churn and needs no audit.
    def churn
      base_entries = @git.entries_at(@base)
      head_entries = @git.entries_at(@head)
      base_pairs = base_entries.to_set { |entry| [entry.subject, entry.mutation] }
      head_pairs = head_entries.to_set { |entry| [entry.subject, entry.mutation] }
      [head_entries.reject { |entry| base_pairs.include?([entry.subject, entry.mutation]) },
       base_entries.reject { |entry| head_pairs.include?([entry.subject, entry.mutation]) }]
    end

    def report(added, dropped, violations)
      @out.puts "ignore-audit: #{added.size} added, #{dropped.size} dropped in #{IGNORE_FILE}"
      violations.each do |violation|
        @out.puts "VIOLATION #{violation.problem}: #{violation.entry.subject} #{violation.entry.mutation}"
      end
    end
  end
end
