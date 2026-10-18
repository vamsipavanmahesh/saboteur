# frozen_string_literal: true

require_relative "../lib/plugins"

RSpec.describe Ohai::NamedPlugin::Network do
  it "doubles the mtu" do
    expect(described_class.new.mtu_size({ "eth0" => { mtu: 10 } }, "eth0")).to eq(20)
  end
end

RSpec.describe Puppet::Type::Package::ProviderPacman do
  it "bumps the hold version" do
    expect(described_class.new.hold_version(4)).to eq(5)
  end
end
