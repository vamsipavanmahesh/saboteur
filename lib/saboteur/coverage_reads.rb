# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Every Coverage.result read goes through here. With the methods report
  # on, the C call hashes each method owner and trusts the return type, so
  # a loaded class whose `hash` does not return an Integer (forem's
  # ReactionCategory, #564) makes every read raise TypeError - a "please
  # report it" crash for what is a bug in the application's code. Refuse
  # instead. The handler runs no app code (an ObjectSpace scan would call
  # #hash/#name on hostile classes) and the error's backtrace names no
  # owning class, so the message stays generic rather than accusing one.
  module CoverageReads
    module_function

    def result(stop:, clear:)
      Coverage.result(stop:, clear:)
    rescue TypeError => e
      raise Error, diagnostic(e)
    end

    def diagnostic(error)
      "Coverage.result raised TypeError (#{error.message}): Coverage's method report hashes every " \
        "method owner and trusts the result, and a loaded class whose #hash does not return an " \
        "Integer (Ruby's #hash contract) breaks it. This is a bug in the application's code, " \
        "not in saboteur."
    end
  end
end
