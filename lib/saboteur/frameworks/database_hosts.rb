# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Frameworks
    # Which database hosts count as local for the Rails integration's refusal
    # to mutate a remote test database (issue #258).
    module DatabaseHosts
      # 0.0.0.0: a listen address, but in a URL it connects to this machine (issue #258).
      LOCAL_HOSTS = ["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].freeze

      module_function

      def local?(host)
        host = host.to_s
        host.empty? || host.start_with?("/") || LOCAL_HOSTS.include?(host.downcase)
      end

      # "name (host host)" per config whose host is not local and not in
      # extra_allowed. Shared by the boot refusal and doctor.
      def remote(configs, extra_allowed = [])
        allowed = extra_allowed.map(&:downcase)
        configs.filter_map do |db|
          host = db.configuration_hash[:host]
          "#{db.name} (host #{host})" unless local?(host) || allowed.include?(host.downcase)
        end
      end
    end
  end
end
