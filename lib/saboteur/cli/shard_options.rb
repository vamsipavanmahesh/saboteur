# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Validates the deterministic candidate-shard selection before the target boots.
    module ShardOptions
      private

      def validate_shard_options
        raise UsageError, "--id cannot be combined with --shard" if options[:id] && config["shard"]

        Engine::Shard.parse(config["shard"]) if config["shard"]
      end
    end
  end
end
