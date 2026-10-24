# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
# v2: keystores.value is bigint; fractional probe value truncated to 0 by type cast, so T1 stores integer 7.
require "rails_helper"

describe TrafficHelper do
  it "PROBE-T1 returns the stored intensity from the keystore" do
    Keystore.put("traffic:intensity", 7)
    expect(TrafficHelper.cached_current_intensity).to eq 7
  end

  it "PROBE-T2 falls back to 0.5 when no intensity is stored" do
    Keystore.find_by(key: "traffic:intensity")&.destroy
    expect(TrafficHelper.cached_current_intensity).to eq 0.5
  end
end
