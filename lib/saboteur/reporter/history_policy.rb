# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # v1 stays readable, but v2 records require versioned operator evidence.
    module HistoryPolicy
      def validate_header(record, fields)
        version = record.is_a?(Hash) && record["version"]
        raise Error, "score history contains an invalid version" unless version.is_a?(Integer) && [1,
                                                                                                   2].include?(version)

        fields(record, version == 2 ? fields + ["operatorPolicy"] : fields)
        validate_policy(record["operatorPolicy"]) if version == 2
      end

      def validate_policy(value)
        return if value.nil?

        fields(value, %w[version selected excluded effective])
        %w[selected excluded effective].each do |key|
          unless value[key].is_a?(Array) && value[key].all?(String)
            raise Error, "score history contains invalid operator policy"
          end
        end
        expected = MutationSource::OperatorRegistry.policy(value["selected"], value["excluded"])
        raise Error, "score history contains invalid operator policy" unless value == expected
      rescue ConfigError
        raise Error, "score history contains invalid operator policy"
      end
    end
  end
end
