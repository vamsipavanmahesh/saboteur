# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  SHA_PATTERN = /\A[0-9a-f]{40}\z/
  MODES = %w[fast full].freeze
  # Reports and logs always go here. It is not configurable, so a run cannot hide source files from
  # the clean-tree check by pointing its output at them.
  OUTPUT_ROOT = "tmp/preflight"

  OPTION_FLAGS = { "--base" => :base, "--head" => :head, "--base-ref" => :base_ref, "--mode" => :mode }.freeze

  Options = Struct.new(:base, :head, :base_ref, :mode, keyword_init: true) do
    def self.parse(argv)
      pairs = argv.each_slice(2).to_a
      raise InvalidInvocation, "options take one value each" unless pairs.all? { |pair| pair.length == 2 }

      values = {}
      pairs.each { |flag, value| assign(values, flag, value) }
      new(**values).tap(&:validate!)
    end

    def self.assign(values, flag, value)
      key = OPTION_FLAGS[flag]
      raise InvalidInvocation, "unknown option #{flag.inspect}" unless key
      raise InvalidInvocation, "option #{flag} given twice" if values.key?(key)

      values[key] = value
    end
    private_class_method :assign

    def validate!
      %i[base head].each do |key|
        next if self[key].to_s.match?(SHA_PATTERN)

        raise InvalidInvocation, "--#{key} must be a full 40-character lowercase SHA"
      end
      raise InvalidInvocation, "--base-ref must be main" unless base_ref == "main"
      raise InvalidInvocation, "--mode must be one of #{MODES.join(', ')}" unless MODES.include?(mode)
    end
  end
end
