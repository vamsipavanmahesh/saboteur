# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Public extension API: implement Base#mutations_for and yield Mutation
# objects built from Edit values. Stable across minor versions.
require_relative "edit"
require_relative "mutation"

module Saboteur
  module MutationSource
    # Extension point. A source yields Mutation objects for a subject.
    # Built-in operators are one source; external sources (for example a
    # service that proposes edits) implement the same method and are
    # registered in config. Every edit must lie inside the subject's byte range.
    class Base
      def name
        self.class.name
      end

      # subject responds to #id, #file, #start_byte, #end_byte, #source.
      def mutations_for(_subject)
        raise NotImplementedError, "#{self.class} must implement #mutations_for"
      end
    end
  end
end
