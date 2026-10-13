# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A minimal stand-in for sorbet-runtime's sig wrapping, for the e2e fixture:
# same shape as the real gem - a wrapper defined inside a sorbet-runtime
# path, dispatching through a signature registry on T::Utils - a fraction of
# the size. The real gem wraps through method_added the same way.
module T
  module Sig
    def sig(*)
      @__pending_sig = true
    end

    def method_added(name)
      super
      return unless @__pending_sig

      @__pending_sig = false
      T::Utils.register(self, name, instance_method(name))
      module_eval("def #{name}(*args, &blk) = T::Utils.invoke(self.class, #{name.inspect}, self, *args, &blk)",
                  __FILE__, __LINE__ + 1)
    end
  end

  module Utils
    @signatures = {}

    class << self
      def register(owner, name, unbound)
        @signatures[[owner, name]] = unbound
      end

      def signature_for_method(method)
        @signatures[[method.owner, method.name]]
      end

      def invoke(owner, name, receiver, *args, &blk)
        @signatures.fetch([owner, name]).bind_call(receiver, *args, &blk)
      end
    end
  end
end
