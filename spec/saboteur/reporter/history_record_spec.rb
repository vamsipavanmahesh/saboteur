# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/reporter/history_record"

RSpec.describe Saboteur::Reporter::HistoryRecord do
  def record
    report = report_of(result_for(:killed, kill_cause: "assertion"),
                       result_for(:killed, replacement: "<", kill_cause: "TypeError"),
                       result_for(:killed, replacement: "=="), result_for(:timeout, replacement: "!="),
                       result_for(:survived, replacement: "true"))
    Saboteur::Reporter::ScoreHistory.new("unused").send(:build, report, "a" * 40, {})
  end

  def invalid(row, message)
    expect { described_class.validate(row) }.to raise_error(Saboteur::Error, message)
  end

  it "strictly validates v2 policy while retaining exact legacy v1 fields" do
    policy = Saboteur::Config.new({ "exclude_operators" => ["range"] }).operator_policy
    current = record.merge("operatorPolicy" => policy, "version" => 2)
    expect { described_class.validate(current) }.not_to raise_error
    expect { described_class.validate(current.except("operatorPolicy").merge("version" => 1)) }.not_to raise_error
    invalid(current.except("operatorPolicy"), /invalid record schema/)
    invalid(current.merge("version" => 3), /invalid version/)
    invalid([], /invalid version/)
    [policy.merge("version" => 1), policy.merge("selected" => "range"),
     policy.merge("selected" => [1]), policy.merge("excluded" => [1]),
     policy.merge("effective" => [1]), policy.merge("effective" => []),
     policy.merge("excluded" => ["typo"]), policy.except("version")].each do |value|
      invalid(current.merge("operatorPolicy" => value), /invalid operator policy|invalid record schema/)
    end
  end

  it "checks header dispatch and policy shape before comparing resolved values" do
    validator = described_class
    fields = validator::FIELDS
    expect(validator).to receive(:fields).with({ "version" => 1 }, fields).ordered
    validator.validate_header({ "version" => 1 }, fields)
    value = { "version" => 2, "operatorPolicy" => nil }
    expect(validator).to receive(:fields).with(value, fields + ["operatorPolicy"]).ordered
    expect(validator).to receive(:validate_policy).with(nil).ordered
    validator.validate_header(value, fields)
    RSpec::Mocks.space.proxy_for(validator).reset
    policy = Saboteur::Config.new.operator_policy
    [policy.merge("version" => "2"), policy.merge("selected" => {}),
     policy.merge("selected" => [nil]), policy.merge("excluded" => [nil]),
     policy.merge("effective" => [nil])].each do |bad|
      expect { validator.validate_policy(bad) }
        .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
    end
    expect { validator.validate_policy(policy.merge("excluded" => ["bad"])) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
    expect(validator).to receive(:fields).with(policy, %w[version selected excluded effective])
    validator.validate_policy(policy)
  end

  it "does not dispatch a policy for legacy rows and refuses version/type guards independently" do
    validator = described_class
    expect(validator).not_to receive(:validate_policy)
    validator.validate_header(record.except("operatorPolicy").merge("version" => 1), validator::FIELDS)
    RSpec::Mocks.space.proxy_for(validator).reset
    policy = Saboteur::Config.new.operator_policy
    validator.fields(policy, %w[version selected excluded effective])
    expect { validator.validate_policy(policy.merge("version" => 3)) }.to raise_error(Saboteur::Error)
    expect { validator.validate_policy(policy.merge("effective" => [Object.new])) }.to raise_error(Saboteur::Error)
  end

  it "validates every string list even when resolved policy equality would agree" do
    validator = described_class
    expected = Saboteur::Config.new.operator_policy
    bad = expected.merge("effective" => [1])
    allow(Saboteur::MutationSource::OperatorRegistry).to receive(:policy).and_return(bad)
    expect { validator.validate_policy(bad) }.to raise_error(Saboteur::Error)
    bad_array = expected.merge("selected" => "all")
    allow(Saboteur::MutationSource::OperatorRegistry).to receive(:policy).and_return(bad_array)
    expect { validator.validate_policy(bad_array) }.to raise_error(Saboteur::Error)
  end

  it "rejects duplicate keys independently of the JSON library default" do
    object = described_class::UniqueObject.new
    object["key"] = 1
    expect { object["key"] = 2 }.to raise_error(Saboteur::Error, /duplicate keys/)
    expect(object).to eq("key" => 1)
  end

  it "allows null commit and rejects invalid dates including valid noncanonical dates" do
    expect { described_class.validate(record.merge("commit" => nil)) }.not_to raise_error
    invalid(record.merge("date" => "2026-10-13T10:00:00+01:00"), /invalid date/)
    invalid(record.merge("commit" => "bad"), /invalid commit/)
    [nil, 12, "bad"].each do |value|
      expect { described_class.date(value) }.to raise_error(Saboteur::Error)
    end
  end

  it "checks every counts field and every breakdown field" do
    base = record
    invalid(base.merge("version" => 1.0), /invalid version/)
    described_class::COUNTS.each do |key|
      invalid(base.merge("counts" => base["counts"].except(key)), /schema/)
      [-1, 1.5, "1", nil].each do |value|
        invalid(base.merge("counts" => base["counts"].merge(key => value)), /invalid count/)
      end
    end
    described_class::BREAKDOWN.each do |key|
      invalid(base.merge("breakdown" => base["breakdown"].except(key)), /schema/)
      invalid(base.merge("breakdown" => base["breakdown"].merge(key => -1)), /invalid (count|score)/)
    end
  end

  it "checks kill classification, tested count, survivors, timeouts and covered score independently" do
    base = record
    %w[assertionKills crashKills unclassifiedKills tested survivors timeouts].each do |key|
      invalid(base.merge("breakdown" => base["breakdown"].merge(key => base["breakdown"][key] + 1)),
              /inconsistent counts/)
    end
    invalid(base.merge("breakdown" => base["breakdown"].merge("score" => 0.1)), /inconsistent counts/)
  end

  it "checks covered numerator and assertion/crash shares independently" do
    base = record
    invalid(base.merge("coveredScore" => 0.1, "breakdown" => base["breakdown"].merge("score" => 0.1)),
            /inconsistent score/)
    %w[assertionShare crashShare].each do |key|
      invalid(base.merge("breakdown" => base["breakdown"].merge(key => 0.1)), /inconsistent share/)
    end
    invalid(base.merge("score" => 1.0), /inconsistent overall/)
    empty = Saboteur::Reporter::ScoreHistory.new("unused").send(:build, report_of, nil, {})
    invalid(empty.merge("score" => 0.5), /inconsistent overall/)
    expect { described_class.validate(empty.merge("score" => 0.0)) }.not_to raise_error
    expect { described_class.validate(base.merge("score" => nil)) }.not_to raise_error
  end

  it "checks primitive helpers independently without converting invalid values" do
    [nil, [], "object"].each do |value|
      expect { described_class.fields(value, []) }.to raise_error(Saboteur::Error, /schema/)
    end
    expect { described_class.fields({}, []) }.not_to raise_error
    [nil, 0, 1, 0.5].each { |value| expect { described_class.fraction(value) }.not_to raise_error }
    [-1, 2, "0.5", []].each { |value| expect { described_class.fraction(value) }.to raise_error(Saboteur::Error, /invalid score/) }
    [0, 1, 2].each { |value| expect { described_class.count(value) }.not_to raise_error }
    [-1, 0.5, "1", nil].each { |value| expect { described_class.count(value) }.to raise_error(Saboteur::Error, /invalid count/) }
  end
  it "uses duplicate-preserving object construction on every imported JSON object" do
    row = record
    expect(JSON).to receive(:parse).with("json", object_class: described_class::UniqueObject).and_return(row)
    expect(described_class.parse("json")).to eq(row)
  end
end
