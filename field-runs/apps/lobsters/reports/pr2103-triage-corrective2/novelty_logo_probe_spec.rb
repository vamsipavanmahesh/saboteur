# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
require "rails_helper"

describe TrafficHelper do
  it "PROBE-N1 Casimir Pulaski Day logo on first Monday of March" do
    monday = Time.zone.local(2026, 3, 2, 12, 0, 0)
    puts "DIAG monday-check: #{monday.monday?} month=#{monday.month} day=#{monday.day}"
    travel_to monday do
      logo = TrafficHelper.novelty_logo
      expect(logo).to include("Casimir_Pulaski_Day")
    end
  end

  it "PROBE-N2 no logo on an ordinary day" do
    travel_to Time.zone.local(2026, 3, 9, 12, 0, 0) do
      expect(TrafficHelper.novelty_logo).to be_nil
    end
  end
end
