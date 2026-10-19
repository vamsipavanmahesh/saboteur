# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::PreviewCommand do
  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the preview command, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(:preview)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(:preview)
  end

  it "lists the operators, off when the config excludes them" do
    Dir.mktmpdir do |dir|
      config = File.join(dir, "saboteur.rb")
      File.write(config, "Saboteur.configure { |c| c.exclude_operators = %w[range] }")
      out = StringIO.new
      code = Saboteur::CLI.new(["run", "--list-operators", "--config", config], out:, err: StringIO.new).call
      expect(code).to eq(0)
      expect(out.string).to match(/^range  off  /)
      expect(out.string).to match(/^comparison  on  /)
    end
  end

  it "creates no --resume directory or manifest for --dry-run (#471)" do
    Dir.mktmpdir do |dir|
      resume = File.join(dir, "state")
      File.write(File.join(dir, "a.rb"), "def a = 1\n")
      out = StringIO.new
      Dir.chdir(dir) { Saboteur::CLI.new(["run", "a.rb", "--dry-run", "--resume", resume], out:, err: StringIO.new).call }
      expect(File).not_to exist(resume)
    end
  end
end
