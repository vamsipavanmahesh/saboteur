# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::SourceScope do
  it "accepts source paths and an empty list" do
    expect(described_class.verify_no_specs!([])).to be_nil
    expect(described_class.verify_no_specs!(%w[lib/a.rb lib/b.rb spec_helper.rb])).to be_nil
  end

  it "refuses spec files, naming each one and pointing at --test" do
    expect { described_class.verify_no_specs!(%w[lib/a.rb spec/a_spec.rb spec/b_spec.rb]) }
      .to raise_error(Saboteur::ConfigError,
                      "spec files are not mutated - pass them with --test, one path per use: " \
                      "spec/a_spec.rb, spec/b_spec.rb")
  end

  it "matches only a path that ends in _spec.rb" do
    expect(described_class.verify_no_specs!(%w[lib/a_spec.rb.bak lib/spec.rb])).to be_nil
    expect { described_class.verify_no_specs!(["x_spec.rb"]) }.to raise_error(Saboteur::ConfigError)
  end
end
