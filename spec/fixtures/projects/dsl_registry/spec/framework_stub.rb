# frozen_string_literal: true

# Minimal stand-ins for the Ohai/Puppet registry DSLs (#700): each builds a
# class, class_evals the block on it and registers it under the constant the
# real frameworks use, so a def in the block re-evaluates through that
# constant. Lives outside lib/ so the stub methods are not subjects.
module Ohai
  module NamedPlugin
  end

  def self.camelize(name)
    name.to_s.split("_").map!(&:capitalize).join
  end

  def self.plugin(name, &block)
    klass = Class.new
    klass.class_eval(&block)
    NamedPlugin.const_set(camelize(name), klass)
  end
end

module Puppet
  class Type
    def self.type(type_name)
      type_class = Class.new(self)
      const_set(Ohai.camelize(type_name), type_class)
      type_class.define_singleton_method(:provide) do |provider_name, **_opts, &block|
        provider = Class.new
        provider.class_eval(&block)
        const_set("Provider#{Ohai.camelize(provider_name)}", provider)
      end
      type_class
    end
  end
end
