# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::DeepSource do
  def parsed(source)
    Prism.parse(source).value
  end

  it "counts the AST depth of nested expressions" do
    shallow = described_class.depth(parsed("a(1)\n"))
    deep = described_class.depth(parsed("a(a(a(1)))\n"))
    expect(deep).to be > shallow
  end

  it "stays flat for sibling statements" do
    expect(described_class.depth(parsed("a(1)\na(1)\na(1)\n")))
      .to eq(described_class.depth(parsed("a(1)\n")))
  end

  it "raises a DeepSourceError naming the file past the limit, and not at it" do
    over = parsed("#{'a(' * 1500}1#{')' * 1500}\n")
    expect { described_class.check!(over, "deep.rb") }
      .to raise_error(Saboteur::DeepSourceError, /deep\.rb/)
    expect { described_class.check!(parsed("a(1)\n"), "fine.rb") }.not_to raise_error
  end

  it "measures depth 0 for a nil program (#719, #730)" do
    expect(described_class.depth(nil)).to eq(0)
  end

  it "measures absolute depth from the root (#719, #730)" do
    expect(described_class.depth(parsed("a(1)\n"))).to eq(5)
  end

  it "keeps the deepest sibling, not the last one popped (#719, #730)" do
    source = "x = 1\n#{'a(' * 50}1#{')' * 50}\n"
    expect(described_class.depth(parsed(source))).to eq(103)
  end

  it "names the file and the limit in the refusal (#719, #730)" do
    expect { described_class.check!(parsed("a(1)\n"), "deep.rb", limit: 4) }
      .to raise_error(Saboteur::DeepSourceError,
                      "deep.rb nests deeper than 4 AST levels; saboteur cannot walk it safely")
  end

  it "allows exactly the finder limit and refuses one level past it (#719)" do
    # Absolute literals: stubbing with the constants would move both sides
    # of the pin together and let +-1 mutants on them survive (#730).
    allow(described_class).to receive(:depth).and_return(2200)
    expect { described_class.check!(nil, "fine.rb") }.not_to raise_error
    allow(described_class).to receive(:depth).and_return(2201)
    expect { described_class.check!(nil, "deep.rb") }
      .to raise_error(Saboteur::DeepSourceError, /deep\.rb/)
  end

  it "allows exactly the mutation limit and refuses one level past it (#719)" do
    allow(described_class).to receive(:depth).and_return(1200)
    expect { described_class.check!(nil, "fine.rb", limit: 1200) }.not_to raise_error
    allow(described_class).to receive(:depth).and_return(1201)
    expect { described_class.check!(nil, "deep.rb", limit: 1200) }
      .to raise_error(Saboteur::DeepSourceError, /deep\.rb/)
  end

  it "refuses a mutation walk earlier than a finder walk (#719)" do
    body = parsed("def m\n  #{'a(' * 700}1#{')' * 700}\nend\n")
    expect { described_class.check!(body, "deep.rb", limit: Saboteur::DeepSource::MAX_MUTATION_DEPTH) }
      .to raise_error(Saboteur::DeepSourceError, /deep\.rb/)
    expect { described_class.check!(body, "deep.rb") }.not_to raise_error
  end
end
