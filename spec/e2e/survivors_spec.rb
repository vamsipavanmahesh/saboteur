# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# saboteur survivors against the real executable (#1150): the subcommand
# stays in step with run - ranked order by default, --color/--no-color
# accepted, the usage line and help name the report path.
RSpec.describe "survivors", :e2e do
  def survivors(dir, *arguments)
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"),
                                      E2EHelpers::EXE, "survivors", *arguments, chdir: dir)
    [out, err, status.exitstatus]
  end

  def help(dir, *arguments)
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"),
                                      E2EHelpers::EXE, "help", *arguments, chdir: dir)
    [out, err, status.exitstatus]
  end

  def write_report(dir)
    mutant = lambda do |id, operator, line, classification|
      { "id" => id, "mutatorName" => operator, "replacement" => "REPLACED",
        "location" => { "start" => { "line" => line, "column" => 3 },
                        "end" => { "line" => line, "column" => 24 } },
        "status" => "Survived", "coveredBy" => ["./spec/order_spec.rb[1:1]"],
        "classification" => classification }
    end
    report = {
      "schemaVersion" => "2", "thresholds" => { "high" => 80, "low" => 60 }, "projectRoot" => dir,
      "files" => { "lib/order.rb" => { "language" => "ruby", "source" => "class Order\nend\n",
                                       "mutants" => [mutant.call("a" * 16, "sum_to_map_sum", 1, "missing_test"),
                                                     mutant.call("b" * 16, "and_to_or", 2, nil)] } },
      "testFiles" => {},
      "saboteur" => { "findings" => { "version" => 1, "survivors" => [
        { "digest" => "b" * 16, "path" => "lib/order.rb", "line" => 2, "subject" => "Order#total",
          "operator" => "and_to_or", "original" => "x", "replacement" => "y" },
        { "digest" => "a" * 16, "path" => "lib/order.rb", "line" => 1, "subject" => "Order#flag",
          "operator" => "sum_to_map_sum", "original" => "x", "replacement" => "y" }
      ], "survivorsTruncated" => 0, "accepted" => [] } }
    }
    path = File.join(dir, "report.json")
    File.write(path, JSON.generate(report))
    path
  end

  it "lists in the report's ranked order by default, and accepts --no-color with plain output" do
    Dir.mktmpdir do |dir|
      path = write_report(dir)
      out, err, status = survivors(dir, path)
      expect(status).to eq(0), err
      expect(out.index("b" * 16)).to be < out.index("a" * 16)

      out, err, status = survivors(dir, path, "--no-color")
      expect(status).to eq(0), err
      expect(out).to include("2 survivors")
      expect(out).not_to include("\e[")
    end
  end

  it "paints the header and the triage label with --color=always" do
    Dir.mktmpdir do |dir|
      out, err, status = survivors(dir, write_report(dir), "--color", "always")
      expect(status).to eq(0), err
      expect(out).to include("\e[1m2 survivors").and include("\e[2mmissing_test\e[0m")
    end
  end

  it "names the report path in the usage error, in --help and in saboteur help survivors" do
    Dir.mktmpdir do |dir|
      _, err, status = survivors(dir)
      expect(status).to eq(2)
      expect(err).to eq("saboteur: survivors expects a report path.\n" \
                        "Usage: saboteur survivors [options] REPORT\n")

      out, _, status = survivors(dir, "--help")
      expect(status).to eq(0)
      expect(out).to include("Usage: saboteur survivors [options] REPORT", "--no-color")

      out, err, status = help(dir, "survivors")
      expect(status).to eq(0), err
      expect(out).to include("saboteur survivors [options] REPORT", "OPTIONS (saboteur survivors)",
                             "--color [MODE]")
    end
  end
end
