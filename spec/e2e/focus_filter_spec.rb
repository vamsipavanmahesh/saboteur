# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run with a focus filter in the suite (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def focus_the_adult_example
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n")
    File.write(File.join(dir, "spec", "focus_helper.rb"), <<~RUBY)
      RSpec.configure { |config| config.filter_run_when_matching :focus }
    RUBY
    path = File.join(dir, "spec", "person_spec.rb")
    File.write(path, File.read(path).sub('it "is an adult at 19"', 'fit "is an adult at 19"'))
  end

  it "runs the whole suite when nothing is focused" do
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n")
    File.write(File.join(dir, "spec", "focus_helper.rb"),
               "RSpec.configure { |config| config.filter_run_when_matching :focus }\n")
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.err).not_to include("focus")
    expect(mutants(run).map { |m| m["status"] }).to include("Killed")
  end

  it "exits 2 and names the focused example instead of scoring a narrowed run" do
    focus_the_adult_example
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.status).to eq(2), run.err
    expect(run.err).to include("focus filter")
    expect(run.err).to match(%r{spec/person_spec\.rb:\d+})
    expect(run.err).to include("--allow-focus")
    expect(run.json).to be_nil
  end

  it "runs the narrowed suite when --allow-focus is given" do
    focus_the_adult_example
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb", "--allow-focus")
    expect(run.status).not_to eq(2), run.err
    expect(run.json).not_to be_nil
  end

  it "does not refuse a run narrowed on purpose with --tag in rspec_args" do
    focus_the_adult_example
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n--tag focus\n")
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.err).not_to include("focus filter")
    expect(run.json).not_to be_nil
  end

  describe "boundaries where RSpec itself decides what runs" do
    def write_suite(body:, rspec_options: "")
      File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n#{rspec_options}")
      File.write(File.join(dir, "spec", "focus_helper.rb"),
                 "RSpec.configure { |config| config.filter_run_when_matching :focus }\n")
      File.write(File.join(dir, "spec", "boundary_spec.rb"), %(require_relative "../lib/people"\n#{body}))
    end

    it "does not refuse an example selector in a file that also has a fit" do
      write_suite(body: <<~RUBY)
        RSpec.describe People::Person do
          it("ordinary") { expect(described_class.new(17).adult?).to be(false) }
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb:3")
      expect(run.err).not_to include("focus filter")
      expect(run.status).not_to eq(2), run.err
    end

    it "still refuses a selector for one file when another selected file has a stray fit" do
      write_suite(body: <<~RUBY)
        RSpec.describe People::Person do
          it("ordinary") { expect(described_class.new(17).adult?).to be(false) }
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb", "--test", "spec/stage_spec.rb:1")
      expect(run.status).to eq(2), run.err
      expect(run.err).to include("focus filter")
    end

    it "does not treat an explicit --example filter as a stray focus" do
      write_suite(rspec_options: "--example adult\n", body: <<~RUBY)
        RSpec.describe People::Person do
          it("adult one") { expect(described_class.new(19).adult?).to be(true) }
          it("other") { expect(described_class.new(17).adult?).to be(false) }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb")
      expect(run.err).not_to include("focus filter")
      expect(run.status).not_to eq(2), run.err
    end

    it "does not count examples that :if or :unless prune anyway as hidden" do
      write_suite(body: <<~RUBY)
        RSpec.describe People::Person do
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
          it("never runs here", if: false) { raise "skipped by :if" }
          it("also never runs", unless: true) { raise "skipped by :unless" }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb")
      expect(run.err).not_to include("focus filter")
      expect(run.status).not_to eq(2), run.err
    end

    it "still refuses when an ordinary example is hidden next to :if pruned ones" do
      write_suite(body: <<~RUBY)
        RSpec.describe People::Person do
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
          it("ordinary") { expect(described_class.new(17).adult?).to be(false) }
          it("never runs here", if: false) { raise "skipped by :if" }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb")
      expect(run.status).to eq(2), run.err
      expect(run.err).to include("1 of 2 examples").and include("boundary_spec.rb:3")
    end

    it "does not count examples that an explicit --tag runs as hidden by the stray fit" do
      write_suite(rspec_options: "--tag slow\n", body: <<~RUBY)
        RSpec.describe People::Person do
          it("slow one", :slow) { expect(described_class.new(17).adult?).to be(false) }
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb")
      expect(run.err).not_to include("focus filter")
      expect(run.status).not_to eq(2), run.err
    end

    it "does not count examples the explicit --tag already leaves out, such as an untagged one" do
      write_suite(rspec_options: "--tag slow\n", body: <<~RUBY)
        RSpec.describe People::Person do
          it("slow one", :slow) { expect(described_class.new(17).adult?).to be(false) }
          fit("stray") { expect(described_class.new(19).adult?).to be(true) }
          it("plain") { expect(described_class.new(20).adult?).to be(true) }
        end
      RUBY
      run = saboteur(dir, "lib/people.rb", "--test", "spec/boundary_spec.rb")
      expect(run.err).not_to include("focus filter")
      expect(run.status).not_to eq(2), run.err
    end
  end
end
