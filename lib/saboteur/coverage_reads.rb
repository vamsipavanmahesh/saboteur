# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Every Coverage.result read goes through here. With the methods report
  # on, the C call hashes each method owner and trusts the return type, so
  # a loaded class whose singleton `hash` does not return an Integer
  # (forem's ReactionCategory, #564) makes every read raise TypeError -
  # a "please report it" crash for an app bug the run cannot outlive.
  # Refuse instead, naming any singleton `hash` override among the loaded
  # classes so the app author finds it at once.
  module CoverageReads
    module_function

    def result(stop:, clear:)
      Coverage.result(stop:, clear:)
    rescue TypeError => e
      raise Error, diagnostic(e)
    end

    def diagnostic(error)
      violators = hash_contract_violators
      cause = if violators.empty?
                "no singleton `hash` override found among the loaded classes - please report it"
              else
                "classes overriding the singleton `hash` contract: #{violators.first(5).join(', ')}"
              end
      "Coverage.result raised TypeError (#{error.message}): with method coverage on, Coverage hashes " \
        "every method owner, so a class defining a singleton `hash` that does not return an Integer " \
        "breaks the run; #{cause}. Restore the Integer contract or rename the method."
    end

    # Classes and modules whose #hash does not come from the default
    # implementation. The default's owner differs by ruby, so anything not
    # owned by Object or Kernel counts as an override.
    def hash_contract_violators
      ObjectSpace.each_object(Module).filter_map do |mod|
        next unless mod.name

        owner = mod.singleton_class.instance_method(:hash).owner
        next if [Object, Kernel].include?(owner)

        "#{mod.name}.hash"
      end.uniq.sort
    end
  end
end
