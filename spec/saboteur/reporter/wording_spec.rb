# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::Wording do
  def breakdown_with(timeouts)
    instance_double(Saboteur::Score, timeouts: timeouts)
  end

  it "says killed when no timeout is in the number (#1146)" do
    expect(described_class.detected_word(breakdown_with(0))).to eq("killed")
  end

  it "names timeouts when one is in the number (#1146)" do
    expect(described_class.detected_word(breakdown_with(2))).to eq("killed or timed out")
  end

  it "claims missing execution, singular (#1145)" do
    expect(described_class.no_execution(1)).to eq("no test executes it")
  end

  it "claims missing execution, plural (#1145)" do
    expect(described_class.no_execution(3)).to eq("no test executes them")
  end

  it "builds the score table's count fragment (#1145)" do
    expect(described_class.untested_note(1)).to eq("1 subject - no test executes it")
    expect(described_class.untested_note(2)).to eq("2 subjects - no test executes them")
  end

  it "builds the clean screen's note with every subject id (#1145)" do
    subjects = [instance_double(Saboteur::Subject, id: "Cart#total"),
                instance_double(Saboteur::Subject, id: "Cart#biggest")]
    expect(described_class.untested_win_note(subjects))
      .to eq("2 subjects not scored - no test executes them: Cart#total, Cart#biggest")
  end
end
