# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Checks::Rubocop do
  def real(name)
    PreflightSupport.fixture_json(name)
  end

  def check_with(status, payload, **flags)
    text = payload.is_a?(String) ? payload : JSON.generate(payload)
    scripted = PreflightSupport::ScriptedRunner.new do |argv|
      PreflightSupport::ScriptedRunner.new.result(argv, status, text, **flags)
    end
    described_class.new(command_runner: scripted).call
  end

  let(:clean) { real("rubocop_clean.json") }
  let(:offending) { real("rubocop_offense.json") }

  it "passes a real clean report with exit 0 (valid control)" do
    expect(check_with(0, clean).status).to eq(:passed)
  end

  it "fails a real report with offenses and exit 1, naming them" do
    result = check_with(1, offending)
    expect([result.status, result.details.first]).to match([:failed, a_string_including("bad_sample.rb:1 ")])
  end

  it "is incomplete when exit 0 hides offenses in the report" do
    expect(check_with(0, offending).status).to eq(:incomplete)
  end

  it "is incomplete when exit 1 comes with a clean report" do
    expect(check_with(1, clean).status).to eq(:incomplete)
  end

  it "is incomplete when no files were inspected, even with zero offenses" do
    empty = clean.merge("files" => [], "summary" => { "offense_count" => 0, "target_file_count" => 0,
                                                      "inspected_file_count" => 0 })
    expect(check_with(0, empty).status).to eq(:incomplete)
  end

  it "is incomplete when counts disagree with the lists" do
    bad = Marshal.load(Marshal.dump(offending))
    bad["summary"]["offense_count"] += 1
    expect(check_with(1, bad).status).to eq(:incomplete)
    bad = Marshal.load(Marshal.dump(clean))
    bad["summary"]["inspected_file_count"] += 1
    expect(check_with(0, bad).status).to eq(:incomplete)
  end

  it "is incomplete for negative or non-integer counts and malformed summaries (no exception)" do
    [-1, "0", nil, 1.5].each do |value|
      bad = Marshal.load(Marshal.dump(clean))
      bad["summary"]["offense_count"] = value
      expect(check_with(0, bad).status).to eq(:incomplete)
    end
    expect(check_with(0, clean.merge("summary" => [])).status).to eq(:incomplete)
    expect(check_with(0, clean.merge("summary" => nil)).status).to eq(:incomplete)
  end

  it "is incomplete for malformed offense entries" do
    bad = Marshal.load(Marshal.dump(offending))
    bad["files"].first["offenses"].first.delete("location")
    expect(check_with(1, bad).status).to eq(:incomplete)
  end

  it "is incomplete for a duplicate key, even if the first value looks fine" do
    text = PreflightSupport.fixture_text("rubocop_clean.json").sub('{"metadata"',
                                                                   '{"summary":{"offense_count":0},"metadata"')
    expect(check_with(0, text).status).to eq(:incomplete)
  end

  ["not json", '{"files": [', "null", "[]", ""].each do |payload|
    it "is incomplete for unparseable or wrongly shaped output #{payload.inspect}" do
      expect(check_with(0, payload).status).to eq(:incomplete)
    end
  end

  it "is incomplete when the command could not run, timed out, was truncated, left processes or had bad encoding" do
    expect(check_with(-1, "", spawn_error: "no bundler").status).to eq(:incomplete)
    expect(check_with(0, clean, timed_out: true).status).to eq(:incomplete)
    expect(check_with(0, clean, truncated: true).status).to eq(:incomplete)
    expect(check_with(0, clean, stray_processes: true).status).to eq(:incomplete)
    expect(check_with(0, clean, invalid_encoding: true).status).to eq(:incomplete)
  end

  it "is incomplete when the process was killed by a signal, whatever the payload says" do
    expect(check_with(-1, offending, signal: 9).status).to eq(:incomplete)
    expect(check_with(-1, clean, signal: 15).status).to eq(:incomplete)
  end

  describe "with the real RuboCop and the repository's own configuration", :integration do
    around do |example|
      Dir.mktmpdir do |directory|
        @directory = directory
        FileUtils.cp(File.expand_path("../../../.rubocop.yml", __dir__), directory)
        example.run
      end
    end

    def real_check
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../Gemfile", __dir__) }
      described_class.new(command_runner: Preflight::CommandRunner.new(directory: @directory, env: env)).call
    end

    it "fails a file that breaks the configured line limit" do
      line = "# #{'x' * 130}"
      File.write(File.join(@directory, "long.rb"),
                 "# SPDX-License-Identifier: MIT\n# frozen_string_literal: true\n\n#{line}\nputs 1\n")
      expect(real_check.status).to eq(:failed)
    end

    it "passes a similar file within the limits" do
      File.write(File.join(@directory, "ok.rb"),
                 "# SPDX-License-Identifier: MIT\n# frozen_string_literal: true\n\nputs 1\n")
      expect(real_check.status).to eq(:passed)
    end
  end
end
