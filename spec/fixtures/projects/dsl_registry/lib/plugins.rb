# frozen_string_literal: true

require_relative "../spec/framework_stub"

Ohai.plugin(:Network) do
  def mtu_size(interfaces, interface)
    interfaces[interface][:mtu] * 2
  end
end

Puppet::Type.type(:package).provide :pacman, parent: nil do
  def hold_version(version)
    version + 1
  end
end
