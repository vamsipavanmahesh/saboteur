# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Explicit test selection and quality-gate flags (#334).
    module ExplicitFileOptions
      private

      def define_explicit_file_options(opts)
        opts.on("--test PATH", "Spec file or directory to run; repeatable. Replaces the configured spec paths") do |v|
          (options[:tests] ||= []) << v
        end
        opts.on("--threshold PERCENT", Float, "Exit 1 when the score is below PERCENT (0-100)") do |v|
          set(:threshold, v)
        end
        Gates.define_options(opts) { |key, value| set(key, value) }
      end
    end
  end
end
