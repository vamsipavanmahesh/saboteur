# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::NextSteps do
  let(:out) { StringIO.new }
  let(:palette) { Saboteur::Reporter::Palette.for(out, mode: :never) }

  def render(report)
    described_class.new(out, palette).call(report)
    out.string
  end

  it "names the replay command with the first live survivor's digest, the ignore file and the agent format" do
    first = result_for(:survived)
    second = result_for(:survived, replacement: "<=")

    text = render(report_of(first, second))

    expect(text).to include("\nNext steps:\n", "saboteur run --id #{first.digest}", "config/saboteur_ignore.rb",
                            "saboteur run --agent")
    expect(text).not_to include(second.digest)
  end

  it "labels the commands as templates: it knows neither the run's selection nor its ignore file" do
    survivor = result_for(:survived)
    text = render(report_of(survivor))
    expect(text).to include("(add this run's own --config, --since, --subject, --test and source options)",
                            "your ignore file (c.ignore_file, default #{Saboteur::Config::IGNORE_FILE})",
                            "saboteur run --agent, with the same options")
    expect(text).not_to include("--format agent")
  end

  it "shows a complete ignore entry: the digest, the survivor's subject and a reason" do
    survivor = result_for(:survived)
    expect(render(report_of(survivor))).to include(
      %(i.mutation "#{survivor.digest}", subject: "#{survivor.subject.id}", reason: "why it is equivalent")
    )
  end

  it "adds the run's seed to the replay command, and leaves it out when there is none" do
    survivor = result_for(:survived)
    [[42, " --seed 42"], [nil, ""]].each do |seed, suffix|
      out.truncate(0)
      out.rewind
      report = Saboteur::Report.new(results: [survivor], subjects: [person_subject], wall_time: 1, root: "/tmp",
                                    seed: seed)
      expect(render(report)).to include("saboteur run --id #{survivor.digest}#{suffix}\n")
    end
  end

  it "skips ignored survivors when picking the one to replay" do
    ignored = result_for(:survived)
    ignored.ignored = "equivalent"
    live = result_for(:survived, replacement: "<=")

    expect(render(report_of(ignored, live))).to include("--id #{live.digest}")
  end

  it "paints the heading with the palette it was given" do
    colored = Saboteur::Reporter::Palette.for(StringIO.new, mode: :always)

    described_class.new(out, colored).call(report_of(result_for(:survived)))

    expect(out.string).to include(colored.paint(:head, "Next steps:"))
    expect(out.string).not_to include("\nNext steps:")
  end

  it "prints nothing when no live survivor is left" do
    ignored = result_for(:survived)
    ignored.ignored = "equivalent"

    expect(render(report_of(result_for(:killed)))).to eq("")
    expect(render(report_of(ignored))).to eq("")
  end
end
