# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "saboteur/version"
require_relative "saboteur/hooks"
require_relative "saboteur/mutation_source/base"
require_relative "saboteur/integration/base"

module Saboteur
  class Error < StandardError; end
end
