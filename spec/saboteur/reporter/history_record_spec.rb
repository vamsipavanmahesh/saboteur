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
