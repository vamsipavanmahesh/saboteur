# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"

RSpec.describe Saboteur::Integration::FocusGuard do
  let(:filter_manager) { RSpec::Core::FilterManager.new }
  let(:group) do
    Class.new(RSpec::Core::ExampleGroup).tap { |klass| klass.set_it_up("guarded", [{}], [], &nil) }
  end
  let(:examples) do
    [{ focus: true, tag: true }, { tag: true }, {}].map.with_index do |metadata, index|
      RSpec::Core::Example.new(group, "example #{index}", metadata, proc {})
    end
  end
  let(:world) { instance_double(RSpec::Core::World, filter_manager: filter_manager, all_examples: examples) }
  let(:explicit_filter_keys) { [] }
  let(:guard) { described_class.new(world: world, explicit_filter_keys: explicit_filter_keys) }

  it "accepts a suite with no inclusion rule" do
    expect(guard.check!).to be_nil
  end

  it "refuses a suite a stray focus rule narrowed, naming the rule, the counts and the focused examples" do
    filter_manager.inclusions.add(focus: true)
    description = RSpec::Core::FilterRules.new(focus: true).description
    expect { guard.check! }.to raise_error(
      Saboteur::ConfigError,
      "a focus filter (#{description}) narrowed the suite: 2 of 3 examples would not run, so the score would " \
      "cover only the ones that do (#{examples.first.location}). Remove the focus, or pass --allow-focus to " \
      "run the narrowed suite anyway."
    )
  end

  it "accepts a stray focus rule that hides nothing" do
    filter_manager.inclusions.add(tag: true)
    filter_manager.inclusions.add(focus: true)
    allow(world).to receive(:all_examples).and_return(examples.first(1))
    expect(guard.check!).to be_nil
  end

  context "when the narrowing rule is named in the run's own arguments" do
    let(:explicit_filter_keys) { [:tag] }

    it "does not call it stray" do
      filter_manager.inclusions.add(tag: true)
      expect(guard.send(:stray_rules)).to eq({})
      expect(guard.check!).to be_nil
    end

    it "still calls an unnamed rule stray beside it" do
      filter_manager.inclusions.add(tag: true)
      filter_manager.inclusions.add(focus: true)
      expect(guard.send(:stray_rules).keys).to eq([:focus])
    end
  end

  it "does not call an example selector stray" do
    filter_manager.add_location(File.expand_path(examples[1].metadata[:absolute_file_path]),
                                [examples[1].metadata[:line_number]])
    expect(guard.send(:stray_rules)).to eq({})
    expect(guard.check!).to be_nil
  end

  it "reads the stray rules once" do
    filter_manager.inclusions.add(focus: true)
    expect(guard.send(:stray_rules)).to equal(guard.send(:stray_rules))
  end

  it "reads the running and hidden examples once" do
    filter_manager.inclusions.add(focus: true)
    expect(guard.send(:running_examples)).to equal(guard.send(:running_examples))
    expect(guard.send(:hidden_examples)).to equal(guard.send(:hidden_examples))
  end

  it "keeps an exclusion out of the hidden examples" do
    filter_manager.inclusions.add(focus: true)
    filter_manager.exclusions.add(tag: true)
    allow(world).to receive(:all_examples).and_return([examples[0], examples[1]])
    expect(guard.check!).to be_nil
  end

  it "keeps a rule named in the run's own arguments when it measures what the focus hides" do
    guard = described_class.new(world: world, explicit_filter_keys: [:tag])
    filter_manager.inclusions.add(tag: true)
    filter_manager.inclusions.add(focus: true)
    expect(guard.check!).to be_nil
  end

  context "when many focused examples share locations" do
    let(:examples) do
      locations = %w[a:1 a:1 a:2 a:3 a:4 a:5 a:6]
      focused = locations.map.with_index do |location, index|
        RSpec::Core::Example.new(group, "focused #{index}", { focus: true }, proc {}).tap do |example|
          allow(example).to receive(:location).and_return(location)
        end
      end
      focused << RSpec::Core::Example.new(group, "other", {}, proc {})
    end

    it "lists each location once, comma separated, at most five" do
      filter_manager.inclusions.add(focus: true)
      expect { guard.check! }.to raise_error(
        Saboteur::ConfigError, /\(a:1, a:2, a:3, a:4, a:5\)\. Remove the focus/
      )
    end
  end
end
