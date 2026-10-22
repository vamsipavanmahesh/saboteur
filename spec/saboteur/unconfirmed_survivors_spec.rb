# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1286: a survivor whose covering tests were not all run is outside the
# score and the exit code, listed on its own, and reported additively.
RSpec.describe "unconfirmed survivors" do
  let(:killed) { result_for(:killed, replacement: "<", kill_cause: "assertion") }
  let(:survivor) { result_for(:survived, replacement: ">") }
  let(:unconfirmed) do
    result_for(:survived, replacement: "!=").with_confirmation("unconfirmed(the confirmation budget is spent)")
  end
  let(:credited) do
    result_for(:survived, replacement: "==")
      .with_confirmation("killed_by_confirmation", status: :killed, killed_by: ["./spec/flow_spec.rb[1:1]"],
                                                   kill_cause: "assertion")
  end

  describe Saboteur::MutantResult do
    it "does not count an unconfirmed survivor as survived" do
      expect(unconfirmed.status).to eq(:survived)
      expect(unconfirmed.unconfirmed?).to be(true)
      expect(unconfirmed.survived?).to be(false)
      expect(unconfirmed.unignored_survivor?).to be(false)
      expect(survivor.unconfirmed?).to be(false)
      expect(survivor.survived?).to be(true)
    end

    it "reports a symbol confirmation as its string name" do
      expect(survivor.with_confirmation(:confirmed).confirmation_state).to eq("confirmed")
    end

    it "keeps a map-silent survivor counted while reporting it unconfirmed" do
      silent = survivor.with_confirmation("unconfirmed_map(no covering tests in the whole-suite map)")
      expect(silent.confirmation_state).to eq("unconfirmed")
      expect(silent.survived?).to be(true)
      expect(silent.unconfirmed?).to be(false)
    end

    it "only a survivor can be unconfirmed" do
      killed_marked = result_for(:killed, kill_cause: "assertion").with_confirmation("unconfirmed(x)")
      expect(killed_marked.unconfirmed?).to be(false)
      expect(killed_marked.survived?).to be(false)
      expect(survivor.with_confirmation("confirmed").unconfirmed?).to be(false)
      expect(survivor.with_confirmation("confirmed").survived?).to be(true)
    end

    it "reads a multi-line reason with parentheses whole, and none from other states" do
      odd = result_for(:survived).with_confirmation("unconfirmed(a (b)\nc)")
      expect(odd.unconfirmed_reason).to eq("a (b)\nc")
      expect(survivor.with_confirmation("confirmed").unconfirmed_reason).to be_nil
      expect(result_for(:survived).with_confirmation("unconfirmed(why)").unconfirmed_reason).to eq("why")
    end

    it "credits the first of several killing tests" do
      two = result_for(:survived).with_confirmation("killed_by_confirmation", status: :killed,
                                                                              killed_by: %w[first second])
      expect(two.credited_test).to eq("first")
      other = result_for(:killed).with_confirmation("confirmed", killed_by: ["t"])
      expect(other.credited_test).to be_nil
    end

    it "names the confirmation state and the reason" do
      expect(unconfirmed.confirmation_state).to eq("unconfirmed")
      expect(unconfirmed.unconfirmed_reason).to eq("the confirmation budget is spent")
      expect(survivor.with_confirmation("confirmed").confirmation_state).to eq("confirmed")
      expect(survivor.confirmation_state).to be_nil
      expect(survivor.unconfirmed_reason).to be_nil
    end

    it "credits a confirmation kill to the first killing test only" do
      expect(credited.confirmation_state).to eq("killed_by_confirmation")
      expect(credited.credited_test).to eq("./spec/flow_spec.rb[1:1]")
      expect(killed.credited_test).to be_nil
      expect(survivor.credited_test).to be_nil
    end
  end

  describe Saboteur::Report do
    it "leaves unconfirmed survivors out of the counts, the score and the survivor lists" do
      report = report_of(killed, survivor, unconfirmed, credited)

      expect(report.counts[:survived]).to eq(1)
      expect(report.counts[:killed]).to eq(2)
      expect(report.survivors).to eq([survivor])
      expect(report.unignored_survivors).to eq([survivor])
      expect(report.unconfirmed_survivors).to eq([unconfirmed])
      expect(report.score).to be_within(0.001).of(2.0 / 3)
    end
  end

  describe Saboteur::Reporter::Stryker do
    it "reports the confirmation fields, with unconfirmed as Ignored and the credited test by id" do
      report = report_of(survivor, unconfirmed, credited)
      mutants = described_class.build(report)[:files].values.flat_map { |file| file[:mutants] }
      by_state = mutants.group_by { |mutant| mutant[:confirmation] }

      expect(by_state.keys).to contain_exactly(nil, "unconfirmed", "killed_by_confirmation")
      expect(by_state["unconfirmed"].first).to include(status: "Ignored",
                                                       statusReason: "unconfirmed: the confirmation budget is spent")
      expect(by_state[nil].first[:status]).to eq("Survived")
      kill = by_state["killed_by_confirmation"].first
      expect(kill[:status]).to eq("Killed")
      expect(kill[:creditedTest]).to eq(kill[:killedBy].first)
    end
  end

  describe Saboteur::Reporter::UnconfirmedSection do
    let(:out) { StringIO.new }
    let(:palette) { Saboteur::Reporter::Palette.new(enabled: false) }

    def many(count)
      Array.new(count) { |n| result_for(:survived, replacement: "x#{n}").with_confirmation("unconfirmed(why)") }
    end

    it "prints nothing without unconfirmed survivors" do
      described_class.new(out, palette).call(report_of(survivor, killed))

      expect(out.string).to eq("")
    end

    it "lists each unconfirmed survivor with its reason, apart from the findings" do
      report = report_of(survivor, unconfirmed)
      described_class.new(out, palette).call(report)

      line = Saboteur::Reporter::MutationText.line(unconfirmed)
      expect(out.string).to eq(
        "unconfirmed (covering tests not run) - 1, not in the score\n  " \
        "#{File.basename(unconfirmed.subject.file)}:#{line} #{unconfirmed.subject.id} - " \
        "#{unconfirmed.digest} (the confirmation budget is spent)\n\n"
      )
    end

    it "caps the list and counts the rest, naming nothing extra at the cap" do
      described_class.new(out, palette).call(report_of(*many(10)))
      expect(out.string.lines.count { |line| line.include?("(why)") }).to eq(10)
      expect(out.string).not_to include("more")

      full = StringIO.new
      described_class.new(full, palette).call(report_of(*many(11)))
      expect(full.string).to include("  ... 1 more\n")
      expect(full.string.lines.count { |line| line.include?("(why)") }).to eq(10)
    end
  end

  describe "the quiet tally part" do
    it "is nil without unconfirmed survivors and counts them otherwise" do
      expect(Saboteur::Reporter::UnconfirmedSection.part(report_of(survivor, killed))).to be_nil
      expect(Saboteur::Reporter::UnconfirmedSection.part(report_of(survivor, unconfirmed))).to eq("1 unconfirmed")
    end
  end

  describe Saboteur::Reporter::Terminal do
    it "prints the unconfirmed section after the findings" do
      out = StringIO.new
      described_class.new(out, color: :never).call(report_of(survivor, unconfirmed))

      expect(out.string).to include("unconfirmed (covering tests not run) - 1, not in the score")
      expect(out.string.index("Survivors")).to be < out.string.index("unconfirmed (covering")
    end

    it "keeps accepted survivors unpluralised in the --quiet line" do
      accepted = Array.new(2) do |n|
        result_for(:survived, replacement: "x#{n}").tap { |r| r.ignored = "equivalent" }
      end
      out = StringIO.new
      described_class.new(out, color: :never, quiet: true).call(report_of(survivor, *accepted))

      expect(out.string).to match(/1 survived, 2 accepted,? /)
      expect(out.string).not_to include("accepteds")
    end

    it "names the unconfirmed count in the --quiet line" do
      out = StringIO.new
      described_class.new(out, color: :never, quiet: true).call(report_of(survivor, unconfirmed))

      expect(out.string).to match(/saboteur: .*1 survived, 1 unconfirmed/)
    end
  end

  describe Saboteur::Integration::RSpec do
    it "refuses a spec file that defines no example group" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "empty_spec.rb"), "# nothing\n")
        integration = described_class.allocate
        allow(integration).to receive_messages(test_files: [], config: double("config", root: dir),
                                               world: double("world", example_groups: []))

        expect { integration.load_spec_files([File.join(dir, "empty_spec.rb")]) }
          .to raise_error(Saboteur::RefusedSpecPath, /defines no example group/)
      end
    end

    it "skips files that are already loaded" do
      integration = described_class.allocate
      allow(integration).to receive_messages(test_files: ["/app/spec/a_spec.rb"], config: double(root: "/app"))
      expect(integration).not_to receive(:load)

      integration.load_spec_files(["/app/spec/a_spec.rb"])
    end

    describe "containment of ids from the cached map (#427)" do
      def integration_for(root)
        described_class.allocate.tap do |integration|
          allow(integration).to receive_messages(test_files: [], config: double(root: root),
                                                 world: double(example_groups: []))
          allow(integration).to receive(:load)
        end
      end

      it "refuses a path outside the project root and never loads it" do
        Dir.mktmpdir do |root|
          Dir.mktmpdir do |elsewhere|
            outside = File.join(elsewhere, "evil_spec.rb")
            File.write(outside, "raise 'ran'\n")
            integration = integration_for(File.realpath(root))

            expect { integration.load_spec_files([outside]) }
              .to raise_error(Saboteur::RefusedSpecPath, /resolves outside the project root/)
            expect(integration).not_to have_received(:load)
          end
        end
      end

      it "refuses a symlink inside the root that points outside it" do
        Dir.mktmpdir do |root|
          Dir.mktmpdir do |elsewhere|
            File.write(File.join(elsewhere, "evil_spec.rb"), "raise 'ran'\n")
            File.symlink(File.join(elsewhere, "evil_spec.rb"), File.join(root, "link_spec.rb"))
            integration = integration_for(File.realpath(root))

            expect { integration.load_spec_files(["./link_spec.rb"]) }
              .to raise_error(Saboteur::RefusedSpecPath, /resolves outside the project root/)
            expect(integration).not_to have_received(:load)
          end
        end
      end

      it "refuses a path that does not exist, and a ../ escape" do
        Dir.mktmpdir do |root|
          integration = integration_for(File.realpath(root))

          expect { integration.load_spec_files(["./missing_spec.rb"]) }
            .to raise_error(Saboteur::RefusedSpecPath, /does not exist under the project root/)
          Dir.mktmpdir do |elsewhere|
            File.write(File.join(elsewhere, "far_spec.rb"), "# far\n")
            escape = Pathname(File.join(elsewhere,
                                        "far_spec.rb")).relative_path_from(Pathname(File.realpath(root))).to_s

            expect { integration.load_spec_files([escape]) }
              .to raise_error(Saboteur::RefusedSpecPath, /outside the project root/)
          end
        end
      end

      it "refuses a planted id that is not a *_spec.rb file, even inside the root" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "evil.rb"), "raise 'ran'\n")
          integration = integration_for(File.realpath(root))

          expect { integration.load_spec_files([File.join(root, "evil.rb")]) }
            .to raise_error(Saboteur::RefusedSpecPath, /not a \*_spec.rb file/)
          expect(integration).not_to have_received(:load)
        end
      end

      it "accepts a spec file under the root" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "ok_spec.rb"), "# ok\n")
          integration = integration_for(File.realpath(root))
          allow(integration).to receive(:world).and_return(double(example_groups: []),
                                                           double(example_groups: [:g]))

          expect { integration.load_spec_files(["./ok_spec.rb"]) }.not_to raise_error
          expect(integration).to have_received(:load).with(File.join(File.realpath(root), "ok_spec.rb"))
        end
      end
    end
  end
end
