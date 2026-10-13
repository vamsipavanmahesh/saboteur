# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "history preflight" do
  it "refuses linked destinations before starting the engine or writing either report" do
    Dir.mktmpdir do |dir|
      history = File.join(dir, "history")
      json = File.join(dir, "report.json")
      html = File.join(dir, "report.html")
      [json, html].each do |destination|
        %i[symlink link].each do |kind|
          File.write(history, "old evidence\n")
          File.public_send(kind, history, destination)
          config = Saboteur::Config.new({ "score_history" => history, "json_report" => json, "html_report" => html })
          cli = Saboteur::CLI.new(["run"], out: StringIO.new, err: StringIO.new)
          allow(cli).to receive(:config).and_return(config)
          expect(Saboteur::Engine).not_to receive(:new)
          expect(cli).not_to receive(:write_html)
          expect(cli).not_to receive(:write_json)
          expect(cli.call).to eq(3)
          expect(File.read(history)).to eq("old evidence\n")
          expect(File.read(destination)).to eq("old evidence\n")
          File.unlink(destination)
        end
      end
    end
  end

  it "rejects malformed history before the mutation run" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "history")
      File.write(path, "bad\n")
      cli = Saboteur::CLI.new(["run", "--score-history", path], out: StringIO.new, err: StringIO.new)
      expect(Saboteur::Engine).not_to receive(:new)
      expect(cli.call).to eq(3)
      expect(File.read(path)).to eq("bad\n")
    end
  end
end
