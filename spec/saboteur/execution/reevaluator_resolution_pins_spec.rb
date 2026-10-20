# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Execution::Reevaluator, "owner resolution" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    ensure
      %i[PinTop PinOuter PinOuter3 PinOuter4 PinOuter5 PinOuter6 PinOuter7].each do |name|
        Object.send(:remove_const, name) if Object.const_defined?(name, false)
      end
    end
  end

  def subject_for(code, id)
    path = File.join(@dir, "pin.rb")
    File.write(path, code)
    Saboteur::SubjectFinder.new.call(path).subjects.find { |s| s.id == id }
  end

  let(:reevaluator) { described_class.new }

  it "resolves an absolute ::Name scope from the top level" do
    load_code = "class PinTop; end\nmodule PinOuter; class ::PinTop; def m = 1; end; end\n"
    subject = subject_for(load_code, "PinTop#m")
    Object.class_eval("class PinTop; end; module PinOuter; end", __FILE__, __LINE__)
    expect(reevaluator.resolve_owner(subject)).to equal(PinTop)
  end

  it "resolves a dotted scope through the enclosing lexical scopes" do
    Object.class_eval("module PinOuter; module Mid; class Leaf; end; end; end", __FILE__, __LINE__)
    subject = subject_for("module PinOuter\n  class Mid::Leaf\n    def m = 1\n  end\nend\n", "PinOuter::Mid::Leaf#m")
    expect(reevaluator.resolve_owner(subject)).to equal(PinOuter::Mid::Leaf)
  end

  it "finds the head of a dotted scope in an outer lexical scope" do
    Object.class_eval("module PinOuter6; module Mid; class Leaf; end; end; module Inner; end; end", __FILE__, __LINE__)
    code = "module PinOuter6\n  module Inner\n    class Mid::Leaf\n      def m = 1\n    end\n  end\nend\n"
    subject = subject_for(code, "PinOuter6::Inner::Mid::Leaf#m")
    expect(reevaluator.resolve_owner(subject)).to equal(PinOuter6::Mid::Leaf)
  end

  it "prefers the innermost enclosing scope that defines the head of a dotted scope" do
    Object.class_eval("module PinOuter7; module Mid; class Leaf; end; end; " \
                      "module Inner; module Mid; class Leaf; end; end; end; end", __FILE__, __LINE__ - 1)
    code = "module PinOuter7\n  module Inner\n    class Mid::Leaf\n      def m = 1\n    end\n  end\nend\n"
    subject = subject_for(code, "PinOuter7::Inner::Mid::Leaf#m")
    expect(reevaluator.resolve_owner(subject)).to equal(PinOuter7::Inner::Mid::Leaf)
  end

  it "reports a dotted scope whose head exists nowhere as a resolution error" do
    subject = subject_for("class PinMissingHead::Leaf\n  def m = 1\nend\n", "PinMissingHead::Leaf#m")
    expect { reevaluator.resolve_owner(subject) }
      .to raise_error(Saboteur::Error, /\Acannot resolve PinMissingHead::Leaf: uninitialized constant PinMissingHead/)
  end

  it "does not fall back to a top-level constant for a missing nested class" do
    Object.class_eval("module PinOuter3; end", __FILE__, __LINE__)
    subject = subject_for("module PinOuter3\n  class String\n    def m = 1\n  end\nend\n", "PinOuter3::String#m")
    expect { reevaluator.resolve_owner(subject) }
      .to raise_error(Saboteur::Error, "cannot resolve PinOuter3::String: uninitialized constant PinOuter3::String")
  end

  it "does not fall back to a top-level constant inside a dotted scope" do
    Object.class_eval("module PinOuter4; module Mid; end; end", __FILE__, __LINE__)
    code = "module PinOuter4\n  class Mid::String\n    def m = 1\n  end\nend\n"
    subject = subject_for(code, "PinOuter4::Mid::String#m")
    expect do
      reevaluator.resolve_owner(subject)
    end.to raise_error(Saboteur::Error, /\Acannot resolve PinOuter4::Mid::String: /)
  end

  it "refuses a scope that is not a class or module" do
    Object.class_eval("module PinOuter5; VALUE = 1; end", __FILE__, __LINE__)
    subject = subject_for("module PinOuter5\n  class VALUE\n    def m = 1\n  end\nend\n", "PinOuter5::VALUE#m")
    expect { reevaluator.resolve_owner(subject) }
      .to raise_error(Saboteur::Error, "PinOuter5::VALUE is not a class or module")
  end
end
