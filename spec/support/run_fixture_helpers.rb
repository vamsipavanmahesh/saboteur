# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module RunFixtureHelpers
  # A run refuses an empty source set (#447), so examples that stub the
  # engine to exercise reporting or provenance still need one real Ruby
  # file under the default include.
  def stub_source_fixture(dir)
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "a.rb"), "# fixture\n")
  end
end

RSpec.configure { |config| config.include RunFixtureHelpers }
