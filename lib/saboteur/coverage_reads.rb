# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Every Coverage.result read goes through here. With the methods report
  # on, the C call hashes each method owner and trusts the return type, so
  # a loaded class whose `hash` does not return an Integer (forem's
  # ReactionCategory, #564) makes every read raise TypeError - a "please
  # report it" crash for what is a bug in the application's code. Refuse
  # instead. The handler must not run app code (an ObjectSpace scan would
  # call #hash/#name on hostile classes), so offender names come only from
  # the error's own backtrace text.
  module CoverageReads
    module_function

    def result(stop:, clear:)
      Coverage.result(stop:, clear:)
    rescue TypeError => e
      raise Error, diagnostic(e)
    end

    # Never accuse a class the error did not name: with no backtrace frame
    # the contract violation is only the usual cause, not a settled fact.
    def diagnostic(error)
      offenders = named_offenders(error)
      naming = if offenders.empty?
                 "The usual cause is a loaded class whose #hash violates Ruby's contract - #hash " \
                   "must return an Integer - but the error text names no offender."
               else
                 "#{offenders.first(5).join(', ')} returned a non-Integer, violating Ruby's " \
                   "contract that #hash must return an Integer."
               end
      "Coverage.result raised TypeError (#{error.message}): Coverage's method report hashes every " \
        "method owner and trusts the result. #{naming} This is a bug in the application's code, " \
        "not in saboteur."
    end

    # Backtrace entries read "path:line:in 'Owner.hash'"; nothing here calls
    # application methods.
    def named_offenders(error)
      Array(error.backtrace).filter_map { |line| line[/in '([\w:.#]*hash)'/, 1] }.uniq
    end
  end
end
