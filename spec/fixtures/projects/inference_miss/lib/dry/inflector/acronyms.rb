# frozen_string_literal: true

module Dry
  class Inflector
    module Acronyms
      def self.acronym?(word)
        %w[api html].include?(word.downcase)
      end
    end
  end
end
