# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Loaded via RUBYOPT before exe/saboteur: makes Saboteur::CLI.new raise,
# to exercise the executable's fallback rescue. Prepended at the first
# class-body end, so the real initialize (defined afterwards) cannot
# overwrite it.
module SaboteurConstructorCrash
  def initialize(*)
    case ENV.fetch("SABOTEUR_EXE_SPEC_RAISE", nil)
    when "interrupt" then raise Interrupt
    when "system_exit" then exit(4)
    else raise StandardError, "injected constructor failure"
    end
  end
end

TracePoint.new(:end) do |event|
  next unless defined?(Saboteur::CLI) && event.self == Saboteur::CLI

  event.disable
  Saboteur::CLI.prepend(SaboteurConstructorCrash)
end.enable
