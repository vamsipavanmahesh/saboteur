# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module MutationSource
    # The byte edits that remove one entry of a comma-separated literal (a
    # hash pair or an array element): the entry itself plus one comma, so
    # the rest of the literal still parses.
    module EntryEdits
      # Removes the entry's bytes.
      def delete_entry(subject, location)
        Edit.new(file: subject.file, start_byte: location.start_offset,
                 end_byte: location.end_offset, replacement: "")
      end

      # The comma after the entry, else the comma before it. `before` is the
      # node preceding the whole entry list (a call's last positional
      # argument before its keywords) when there is one. An entry with no
      # separator - the only entry, or whitespace-separated as in %w[] -
      # needs no second edit.
      def entry_separator(entries, index, ending, tokens, before: nil)
        entry = entries[index]
        after = comma_between(entry.location.end_offset, ending, tokens)
        return after if after

        previous = entries[0...index].last || before
        comma_between(previous.location.end_offset, entry.location.start_offset, tokens) if previous
      end

      def comma_between(first, last, tokens)
        tokens.find do |token|
          token.type == :COMMA && token.location.start_offset >= first && token.location.end_offset <= last
        end&.location
      end

      # A heredoc's body lives on later lines: removing the entry that opens
      # it would leave the body behind, so such entries are left alone.
      def heredoc?(node)
        (node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")) ||
          node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
