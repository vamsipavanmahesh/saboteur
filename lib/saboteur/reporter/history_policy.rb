# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # v1 stays readable, but v2 records require versioned operator evidence.
    # A policy stamped with an older POLICY_VERSION is shape-checked only:
    # the operator set has moved on, so it never recomputes equal - and it
    # never compares equal to a current run's policy either, which is what
    # keeps trend from mixing operator sets (#135).
    module HistoryPolicy
      def validate_header(record, fields)
        version = record.is_a?(Hash) && record["version"]
        raise Error, "score history contains an invalid version" unless version.is_a?(Integer) && [1,
                                                                                                   2].include?(version)

        fields(record, version == 2 ? fields + ["operatorPolicy"] : fields)
        validate_policy(record["operatorPolicy"]) if version == 2
      end

      def validate_policy(value)
        raise Error, "score history contains invalid operator policy" unless value.is_a?(Hash)

        fields(value, %w[version selected excluded effective])
        policy_version = value["version"]
        unless policy_version.is_a?(Integer) &&
               policy_version.between?(1, MutationSource::OperatorRegistry::POLICY_VERSION)
          raise Error, "score history contains invalid operator policy"
        end
        raise Error, "score history contains invalid operator policy" if value["effective"].empty?

        lists = value.values_at("selected", "excluded", "effective")
        unless lists.all? { |list| list.is_a?(Array) && list.all?(String) }
          raise Error, "score history contains invalid operator policy"
        end

        return if policy_version != MutationSource::OperatorRegistry::POLICY_VERSION

        expected = MutationSource::OperatorRegistry.policy(value["selected"], value["excluded"])
        raise Error, "score history contains invalid operator policy" unless value == expected
      rescue ConfigError, NoMethodError, TypeError
        raise Error, "score history contains invalid operator policy"
      end
    end
  end
end
