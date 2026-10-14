# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/visibility"

# The values are never asserted: only the visibility is, so a mutant of a
# body survives unless re-evaluating it changed who may call the method.
RSpec.describe "visibility" do
  let(:hidden) { Hidden.new }

  it "keeps instance methods private, protected and public" do
    hidden.public_value
    hidden.run_hidden
    hidden.compare(Hidden.new)
    %i[private_value inline_private_value private_def_value].each do |name|
      expect(Hidden.private_method_defined?(name)).to be(true), name.to_s
      expect { hidden.public_send(name) }.to raise_error(NoMethodError)
    end
    expect(Hidden.protected_method_defined?(:protected_value)).to be(true)
    expect { hidden.protected_value }.to raise_error(NoMethodError)
    expect(Hidden.public_method_defined?(:public_value)).to be(true)
  end

  it "keeps class methods private or public" do
    Hidden.singleton_public_value
    expect(Hidden.singleton_class.private_method_defined?(:class_private_value)).to be(true)
    expect(Hidden.singleton_class.private_method_defined?(:singleton_private_value)).to be(true)
    expect { Hidden.class_private_value }.to raise_error(NoMethodError)
    expect { Hidden.singleton_private_value }.to raise_error(NoMethodError)
    expect(Hidden.singleton_class.public_method_defined?(:singleton_public_value)).to be(true)
  end

  it "keeps module_function copies: a public singleton and a private instance method" do
    Helper.function_value
    Helper.self_extended_probe
    host = Class.new { include Helper }.new
    expect { host.function_value }.to raise_error(NoMethodError)
    expect(Helper.singleton_class.public_method_defined?(:function_value)).to be(true)
    expect(Helper.private_method_defined?(:function_value)).to be(true)
  end

  it "keeps extend self modules: public methods callable on the module, private ones not" do
    SelfExtended.open_value
    SelfExtended.send(:closed_value)
    expect { SelfExtended.closed_value }.to raise_error(NoMethodError)
    expect(SelfExtended.private_method_defined?(:closed_value)).to be(true)
    expect(SelfExtended.public_method_defined?(:open_value)).to be(true)
  end
end
