# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
require "rails_helper"

describe ApplicationHelper do
  describe "link_to_different_page class handling (verification probe)" do
    def stub_current_path(path)
      allow(helper).to receive(:request).and_return(double(path: path))
    end

    it "PROBE-A1 preserves an explicit class on the link" do
      stub_current_path("/top")
      result = helper.link_to_different_page("Top", "/top", class: "foo")
      expect(result).to have_css("a.foo")
    end

    it "PROBE-A2 emits no class attribute when no class is given" do
      stub_current_path("/top")
      result = helper.link_to_different_page("Top", "/top")
      expect(result).to have_no_css("a[class]")
    end
  end
end
