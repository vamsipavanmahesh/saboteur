# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "diff"
require_relative "mutation_text"
require_relative "survivor_classification"
require_relative "survivor_hints"

module Saboteur
  module Reporter
    # Survivors as per-statement blocks: the finding is the code. Each block
    # is numbered and headed by file:line and subject, shows the enclosing
    # def with the changed line as a -/+ pair (a ^^^ marker under the exact
    # changed span), a per-operator "why it matters" sentence, the tests that
    # covered the line and still passed, and an optional hint. Sibling
    # mutants on the same statement collapse onto one dim line;
    # --all-mutants gives every survivor its own block. Accepted
    # (ignored) survivors get one quoted dim line each, never a block.
    class SurvivorList
      # Rendered rows in the method fence, elision markers included.
      FENCE_CAP = 10

      # "- " + three right-aligned line-number columns + " ".
      GUTTER_WIDTH = 6

      # Sibling digests named on the collapse line; the rest are a count.
      SIBLING_DIGEST_CAP = 3

      def initialize(out, palette, all_mutants: false, classifier: SurvivorClassification)
        @out = out
        @palette = palette
        @all_mutants = all_mutants
        @classifier = classifier
      end

      # Survivors in report (ranked) order; accepted ones trail as dim lines.
      def call(report, survivors)
        return if survivors.empty?

        live, accepted = survivors.partition(&:unignored_survivor?)
        @out.puts @palette.paint(:head, "Survivors (#{live.size}) - changes your tests did not catch")
        blocks = groups(live)
        blocks.each_with_index { |group, index| block(report, group, index + 1, blocks.size) }
        accepted_section(report, accepted)
        hinted = live.select { |result| hint_for(result) }
        @out.puts "\n#{@palette.paint(:dim, SurvivorHints::CAVEAT)}" if hinted.any?
      end

      private

      # Statement + status is the group key: every survivor here survived.
      # --all-mutants restores the per-mutant list: no collapse, one block
      # each, in the same ranked order.
      def groups(live)
        return live.map { |result| [result] } if @all_mutants

        live.group_by { |result| [result.subject.id, MutationText.line(result)] }.values
      end

      def block(report, group, rank, total)
        first = group.first
        line = MutationText.line(first)
        path = relative(first.subject.file, report.root)
        @out.puts "\n#{@palette.paint(:head, "#{rank}. #{path}:#{line}")} #{first.subject.id} " \
                  "#{@palette.paint(:dim, label_suffix(first, rank, total))}".rstrip
        fence(first, line)
        @out.puts "  #{@palette.paint(:dim, "why it matters: #{why(first.mutation.operator)}")}"
        changed_lines(report, path, first)
        covered(group)
        hint_line(first)
        siblings(report, group)
      end

      def label_suffix(result, rank, total)
        label = @classifier.label(result)
        # rank counts printed blocks, so the total must too: a collapsed
        # statement prints one block for several mutants, and "#3 of 33"
        # mixed the units (#1147).
        parts = [label, "##{rank} of #{total} #{total == 1 ? 'block' : 'blocks'}"].compact
        reason = SurvivorHints.label_reason(label)
        "[#{parts.join(" \u00B7 ")}#{": #{reason}" if reason}]"
      end

      # The enclosing def with the changed line as a -/+ pair; longer
      # methods keep head, the changed line and tail, the middle elided.
      def fence(result, changed_line)
        all = result.subject.source.lines
        index = changed_line - result.subject.start_line
        lines = fenced_rows(all, index).map do |row|
          if row == :elision
            @palette.paint(:dim, "#{gutter(' ', '')}...")
          elsif row == index
            changed_pair(result, all[row], changed_line)
          else
            @palette.paint(:dim, "#{gutter(' ', result.subject.start_line + row)}#{all[row].rstrip}")
          end
        end
        @out.puts lines
      end

      # Head, the changed line with one neighbour each side, and the tail
      # always survive the cap; only true middle lines elide.
      def fenced_rows(all, changed_index)
        return (0...all.size).to_a if all.size <= FENCE_CAP

        keep = [0, 1, 2, changed_index - 1, changed_index, changed_index + 1, all.size - 2, all.size - 1]
               .uniq.grep(0...all.size)
        keep.each_with_object([]) do |i, rows|
          rows << :elision if rows.any? && !rows.include?(i - 1)
          rows << i
        end
      end

      def changed_pair(result, original_line, line_number)
        replacement_line = replaced_line(result, original_line, line_number)
        minus = @palette.paint(:fail, "#{gutter('-', line_number)}#{original_line.rstrip}")
        return [minus] if replacement_line.strip.empty?

        plus = "#{gutter('+', line_number)}#{replacement_line.rstrip}"
        span = Diff.edit_span(line_start(result, line_number), MutationText.sorted_edits(result))
        column, width = char_span(original_line, span)
        [minus,
         @palette.paint(:pass, plus) +
           @palette.paint(:dim, "   #{result.mutation.operator} \u00B7 #{result.digest}"),
         @palette.paint(:pass, "#{' ' * (GUTTER_WIDTH + column)}#{'^' * width}")]
      end

      # The span comes in file bytes; the caret lines up in printed
      # characters, so a multibyte character before the edit must not push
      # the caret one column right per byte.
      def char_span(line, (offset, length))
        bytes = line.b
        # scrub() would not change the count: invalid bytes count as one
        # character with or without it.
        decode = ->(part) { part.force_encoding(line.encoding).length }
        [decode.call(bytes.byteslice(0, offset)), decode.call(bytes.byteslice(offset, length))]
      end

      # The changed line with this mutant's edits applied, so a line count
      # change in the full def text cannot misalign the pair.
      def replaced_line(result, original_line, line_number)
        start = line_start(result, line_number)
        MutationText.sorted_edits(result).reverse_each.reduce(original_line.b) do |text, edit|
          from = edit.start_byte - start
          text[0...from].to_s + edit.replacement.b + text[(from + (edit.end_byte - edit.start_byte))..].to_s
        end.force_encoding(original_line.encoding)
      end

      # Byte offset where the printable form of this def line starts. The
      # first line of a subject begins at the def keyword (subject.source is
      # not the whole file line), later lines start at the file line start.
      def line_start(result, line_number)
        subject = result.subject
        return subject.start_byte if line_number == subject.start_line

        subject.file_source.lines.take(line_number - 1).join.bytesize
      end

      def gutter(sign, number)
        "#{sign} #{number.to_s.rjust(3)} "
      end

      def why(operator)
        SurvivorHints.why(operator)
      end

      # The tests that ran with the mutant applied and still passed: the
      # missing assertion belongs in one of them. Line coverage can
      # overstate which tests exercise the line, so the list is a lead.
      # In diff mode: the changed lines this mutant touches.
      def changed_lines(report, path, result)
        lines = report.changed_lines_for(result)
        return if lines.empty?

        shown = lines.first(3).map { |line| "#{path}:#{line}" }.join(", ")
        more = lines.size - 3
        suffix = more.positive? ? " (+#{more} more)" : ""
        @out.puts @palette.paint(:dim, "  changed #{lines.one? ? 'line' : 'lines'}: #{shown}#{suffix}")
      end

      # The covering tests are a group union (#502): the first names where an
      # assertion would pin the change, the count says the rest also passed.
      def covered(group)
        tests = group.flat_map(&:covered_by).uniq
        return if tests.empty?

        first = group.find { |result| result.covered_by.include?(tests.first) }
        @out.puts "  covered by #{tests.first} #{@palette.paint(:dim, "- #{passed_phrase(first)}")}"
        line = more_covered_line(group, tests)
        @out.puts @palette.paint(:dim, "  #{line}") if line
      end

      # The verdict names what this run did: executed is nil when the run
      # did not record which tests ran, so only the bare verdict is safe.
      def more_covered_line(group, tests)
        more = tests.size - 1
        return unless more.positive?

        executed = group.filter_map(&:executed).flatten.uniq
        ran = tests.drop(1).count { |test| executed.include?(test) }
        suffix = if executed.empty?
                   # Only a run that recorded nothing about this group may
                   # keep the bare verdict; recorded-but-not-run is named.
                   if group.all? { |result| result.executed.nil? }
                     ", all passed"
                   else
                     " (none ran this run)"
                   end
                 elsif ran == more
                   " (all #{more} ran, all passed)"
                 elsif ran.zero?
                   " (none ran this run)"
                 else
                   " (#{ran} ran, all passed; #{more - ran} did not run this run)"
                 end
        "+#{more} more covered#{suffix}"
      end

      def passed_phrase(result)
        result.reused? ? "passed in an earlier run (--incremental)" : "ran, still passed"
      end

      def hint_line(result)
        text = hint_for(result)
        @out.puts "  #{@palette.paint(:info, "\u2192")} #{text}" if text
      end

      def hint_for(result)
        SurvivorHints.for_label(result.mutation.operator, label: @classifier.label(result),
                                                          coarse: result.mutation.coarse)
      end

      def siblings(report, group)
        rest = group.drop(1)
        return if rest.empty?

        list = rest.first(SIBLING_DIGEST_CAP)
                   .map { |result| "#{result.digest} (#{result.mutation.operator})" }.join(", ")
        overflow = rest.size - SIBLING_DIGEST_CAP
        list = "#{list} (+#{overflow} more)" if overflow.positive?
        @out.puts @palette.paint(:dim, "  #{rest.size} more #{rest.one? ? 'mutant' : 'mutants'} here: #{list}")
        @out.puts @palette.paint(:dim, "       expand: saboteur run --all-mutants#{' --since main' if report.diff?}")
      end

      # Accepted (ignored) survivors stay visible but never earn a block:
      # one quoted dim line each, marked not scored.
      def accepted_section(report, accepted)
        return if accepted.empty?

        @out.puts ""
        entries = accepted.map do |result|
          "#{relative(result.subject.file, report.root)}:#{MutationText.line(result)} " \
            "#{result.mutation.operator} - \"#{result.ignored}\""
        end
        if accepted.one?
          @out.puts @palette.paint(:dim, "Accepted (1, not scored): #{entries.join}")
        else
          lines = ["Accepted (#{accepted.size}, not scored):"] + entries.map { |entry| "  #{entry}" }
          @out.puts @palette.paint(:dim, lines.join("\n"))
        end
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
