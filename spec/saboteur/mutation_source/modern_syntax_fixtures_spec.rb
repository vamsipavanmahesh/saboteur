# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Modern syntax the 0.4.0 review verified by hand (#119), locked as a spec.
RSpec.describe Saboteur::MutationSource::Builtin, "modern syntax fixtures" do
  # Every mutant must parse, differ from the method, and change only the
  # bytes of its edit: the text before and after the edited span is intact.
  def expect_clean_mutants(subject)
    proposals = described_class.new.mutations_for(subject)
    expect(proposals).not_to be_empty
    proposals.each do |mutation|
      text = subject.apply(mutation.edits)
      expect(text).not_to eq(subject.source), mutation.operator
      expect(Prism.parse(text)).to be_success, "#{mutation.operator}: #{text}"
    end
    proposals
  end

  describe "modern syntax (#119)" do
    {
      "argument forwarding" => "def m(...) = other(...)\n  def other(a, b = 1) = a + b",
      "anonymous splats and block" => "def m(*, **, &) = other(*, **, &)\n  def other(*a, **o, &b) = a.size + o.size",
      "case/in with a guard" =>
        "def m(a)\n    case a\n    in Integer => n if n > 1 then n + 1\n    in [x, *] then x\n    " \
        "else 0\n    end\n  end",
      "numbered and it parameters" => "def m(a) = a.map { _1 + 1 }.select { it > 1 }"
    }.each do |name, body|
      it "produces parsing mutants for #{name}" do
        subject = subjects_in("class K\n  #{body}\nend\n").first
        expect(subject).not_to be_nil
        expect_clean_mutants(subject)
      end
    end

    # Parsing is not judging: each mutant must also re-evaluate into the running
    # class under both strategies and run, so a test can kill or miss it.
    {
      "argument forwarding" => ["def m(...) = other(...)\n  def other(a, b = 1) = a + b", [2], 3],
      "anonymous splats and block" =>
        ["def m(*, **, &) = other(*, **, &)\n  def other(*a, **o, &b) = a.size + o.size", [1, 2, { k: 3 }], 3],
      "case/in with a guard" =>
        ["def m(a)\n    case a\n    in Integer => n if n > 1 then n + 1\n    in [x, *] then x\n    " \
         "else 0\n    end\n  end", [5], 6],
      "numbered and it parameters" => ["def m(a) = a.map { _1 + 1 }.select { it > 2 }", [[1, 2, 3]], [3, 4]]
    }.each do |name, (body, args, expected)|
      %w[class_eval nesting].each do |strategy|
        it "re-evaluates and runs the mutants of #{name} with the #{strategy} strategy" do
          skip "`it` needs Ruby 3.4" if body.include?("it >") && RUBY_VERSION < "3.4"

          subject = subjects_in("class ModernK\n  #{body}\nend\n").first
          reeval = Saboteur::Execution::Reevaluator.new(strategy)
          outcomes = described_class.new.mutations_for(subject).map do |mutation|
            load subject.file
            expect(ModernK.new.m(*args)).to eq(expected)
            reeval.call(subject, subject.apply(mutation.edits))
            begin
              ModernK.new.m(*args)
            rescue StandardError => e
              e.class
            end
          end
          expect(outcomes).not_to be_empty
          expect(outcomes).to include(satisfy { |outcome| outcome != expected })
        ensure
          Object.send(:remove_const, :ModernK) if defined?(ModernK)
        end
      end
    end
  end
end
