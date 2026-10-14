# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/reporter/history_record"

RSpec.describe Saboteur::Reporter::HistoryPolicy do
  let(:record) { Saboteur::Reporter::HistoryRecord }
  let(:fields) { Saboteur::Reporter::HistoryRecord::FIELDS }

  def policy(selected = ["range"], excluded = [])
    Saboteur::MutationSource::OperatorRegistry.policy(selected, excluded)
  end

  def v1_record(overrides = {})
    fields.to_h { |key| [key, key == "version" ? 1 : "x"] }.merge(overrides)
  end

  def v2_record(overrides = {})
    v1_record({ "version" => 2, "operatorPolicy" => policy }.merge(overrides))
  end

  it "accepts valid version 1 and version 2 headers" do
    expect { record.validate_header(v1_record, fields) }.not_to raise_error
    expect { record.validate_header(v2_record, fields) }.not_to raise_error
  end

  it "rejects an unsupported version, even one equal to a supported float" do
    expect { record.validate_header(v1_record("version" => 3), fields) }
      .to raise_error(Saboteur::Error, "score history contains an invalid version")
    expect { record.validate_header(v2_record("version" => 2.0), fields) }
      .to raise_error(Saboteur::Error, "score history contains an invalid version")
  end

  it "rejects a non-hash record" do
    expect { record.validate_header(["version", 2], fields) }
      .to raise_error(Saboteur::Error, "score history contains an invalid version")
  end

  it "rejects a v2 record missing a base field" do
    expect { record.validate_header(v2_record.except("date"), fields) }
      .to raise_error(Saboteur::Error, "score history contains an invalid record schema")
  end

  it "rejects a v2 record whose operator policy is null" do
    expect { record.validate_header(v2_record("operatorPolicy" => nil), fields) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
  end

  it "rejects a policy that is not an object" do
    expect { record.validate_policy(nil) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
    expect { record.validate_policy("range") }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
  end

  it "rejects a policy with the wrong schema" do
    expect { record.validate_policy(policy.except("selected")) }
      .to raise_error(Saboteur::Error, "score history contains an invalid record schema")
  end

  it "rejects a policy whose lists are not string arrays" do
    expect { record.validate_policy(policy.merge("selected" => "range")) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
    expect { record.validate_policy(policy.merge("excluded" => nil)) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
  end

  it "rejects a policy with an empty effective set" do
    empty = Saboteur::MutationSource::OperatorRegistry.policy(
      [], Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys
    )
    expect { record.validate_policy(empty) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
  end

  it "rejects a policy whose effective set does not match its selection" do
    tampered = policy(%w[range comparison]).then { |p| p.merge("effective" => p["effective"].reverse) }
    expect { record.validate_policy(tampered) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy")
  end

  it "rejects a policy naming an unknown operator as a history error, not a config error" do
    expect { record.validate_policy(policy.merge("selected" => ["nope"])) }
      .to raise_error(Saboteur::Error, "score history contains invalid operator policy") { |error|
        expect(error).not_to be_a(Saboteur::ConfigError)
      }
  end
end
