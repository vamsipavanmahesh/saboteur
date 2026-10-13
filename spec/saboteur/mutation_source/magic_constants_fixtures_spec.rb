# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Magic constants the 0.4.0 review verified by hand (#120), locked as a spec.
RSpec.describe Saboteur::MutationSource::Builtin, "magic constant fixtures" do
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

  describe "magic constants (#120)" do
    it "leaves __method__, __dir__ and __FILE__ readable in every mutant" do
      source = "class K\n  def m(a)\n    name = __method__\n    root = File.join(__dir__, \"x\")\n    " \
               "[name, root, __FILE__, a + 1]\n  end\nend\n"
      subject = subjects_in(source).first
      expect_clean_mutants(subject)
      arithmetic = mutated_texts(subject).find { |operator, _| operator == "arithmetic" }
      expect(arithmetic.last).to include("a - 1", "__method__", "__dir__", "__FILE__")
    end
  end
end
