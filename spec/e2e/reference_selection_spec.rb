# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "spec selection by constant reference", :e2e do
  # No spec carries the file's name, but one spec reads its constant: the run
  # goes ahead with that spec and says so in the report, not only on stderr.
  def project_with_reader
    dir = copy_fixture("inference_miss")
    FileUtils.rm_rf(File.join(dir, "spec", "integration"))
    FileUtils.mkdir_p(File.join(dir, "spec", "features"))
    FileUtils.mv(File.join(dir, "spec", "unit", "inflector", "acronyms_spec.rb"),
                 File.join(dir, "spec", "features", "knows_acronyms_spec.rb"))
    FileUtils.rm_rf(File.join(dir, "spec", "unit"))
    File.write(File.join(dir, "spec", "features", "knows_acronyms_spec.rb"),
               File.read(File.join(dir, "spec", "features", "knows_acronyms_spec.rb"))
                   .sub("../../../lib", "../../lib"))
    dir
  end

  it "runs the reading spec and carries the note in the JSON warnings" do
    run = saboteur(project_with_reader, "lib/dry/inflector/acronyms.rb")

    expect(run.status).to eq(0), run.err
    note = run.json.fetch("warnings").find { |warning| warning.include?("selected by constant reference or require") }
    expect(note).to include("lib/dry/inflector/acronyms.rb", "spec/features/knows_acronyms_spec.rb")
    expect(run.err).to include("selected by constant reference or require")
  end

  it "carries the note in the agent payload too" do
    run = saboteur(project_with_reader, "lib/dry/inflector/acronyms.rb", "--agent")

    expect(JSON.parse(run.out).fetch("warnings").join).to include("selected by constant reference or require")
  end
end
