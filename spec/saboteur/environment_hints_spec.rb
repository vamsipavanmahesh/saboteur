# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::EnvironmentHints do
  def with_root(files)
    Dir.mktmpdir do |dir|
      files.each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      yield dir
    end
  end

  # APFS and some other filesystems reject filenames that are not valid
  # UTF-8 or contain control characters at creation time (#718 macOS CI);
  # the raw-name cases cannot run there.
  def write_named(dir, name)
    File.write(File.join(dir, name), "")
  rescue Errno::EILSEQ, Errno::EINVAL
    skip "this platform rejects filenames that are not valid UTF-8"
  end

  describe ".bundler (#598)" do
    it "warns when a lockfile exists and Bundler is not loaded" do
      with_root("Gemfile.lock" => "GEM\n") do |dir|
        hint = described_class.bundler(dir, bundler_loaded: false)
        expect(hint).to include("Gemfile.lock", "Bundler is not loaded", "bundle exec saboteur run")
      end
    end

    it "stays quiet inside the bundle and without a lockfile" do
      with_root("Gemfile.lock" => "GEM\n") do |dir|
        expect(described_class.bundler(dir, bundler_loaded: true)).to be_nil
      end
      with_root("lib/x.rb" => "x = 1\n") do |dir|
        expect(described_class.bundler(dir, bundler_loaded: false)).to be_nil
      end
    end
  end

  describe ".all" do
    it "returns no hints when detection itself raises (advisory only)" do
      allow(described_class).to receive(:bundler).and_raise(RuntimeError, "disk went away")
      expect(described_class.all("/whatever", bundler_loaded: true, env: {})).to eq([])
    end

    it "combines both hints" do
      with_root("Gemfile.lock" => "GEM
", "Appraisals" => "appraise \"a\" do\nend\n") do |dir|
        hints = described_class.all(dir, bundler_loaded: false, env: {})
        expect(hints.size).to eq(2)
        expect(hints.first).to include("Bundler is not loaded")
        expect(hints.last).to include("Appraisal gemfiles found", "is not set")
      end
    end

    it "is empty on a clean project" do
      with_root("lib/x.rb" => "x = 1\n") do |dir|
        expect(described_class.all(dir, bundler_loaded: true, env: {})).to eq([])
      end
    end
  end

  describe ".appraisal (#609)" do
    let(:files) do
      { "Appraisals" => "appraise \"a\" do\nend\n",
        "gemfiles/rails_7_2.gemfile" => "gem \"rspec\"\n",
        "gemfiles/rails_8_0.gemfile" => "gem \"rspec\"\n" }
    end

    it "names the files and both command forms when BUNDLE_GEMFILE is unset" do
      with_root(files) do |dir|
        expect(described_class.appraisal(dir, env: {})).to eq(
          "Appraisal gemfiles found (Appraisals, gemfiles/rails_7_2.gemfile, gemfiles/rails_8_0.gemfile) " \
          "but BUNDLE_GEMFILE is not set: run `BUNDLE_GEMFILE=gemfiles/<name>.gemfile bundle exec saboteur run` " \
          "or `bundle exec appraisal <name> saboteur run`"
        )
      end
    end

    it "fires with only an Appraisals file or only gemfiles/" do
      with_root("Appraisals" => "appraise \"a\" do\nend\n") do |dir|
        expect(described_class.appraisal(dir, env: {})).to include("(Appraisals)")
      end
      with_root("gemfiles/a.gemfile" => "gem \"rspec\"\n") do |dir|
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to include("(gemfiles/a.gemfile)")
        expect(hint).not_to include("Appraisals")
      end
    end

    it "names the outside setting when BUNDLE_GEMFILE points elsewhere" do
      with_root(files) do |dir|
        hint = described_class.appraisal(dir, env: { "BUNDLE_GEMFILE" => "Gemfile" })
        expect(hint).to include("but BUNDLE_GEMFILE points outside gemfiles/ (Gemfile): run")
      end
    end

    it "escapes terminal control characters in gemfile names (Pod 1 security)" do
      evil = "a\e[2J\e]0;pwn\a\nsaboteur: warning: all clear.gemfile"
      with_root("Appraisals" => "appraise \"a\" do\nend\n") do |dir|
        Dir.mkdir(File.join(dir, "gemfiles"))
        write_named(File.join(dir, "gemfiles"), evil)
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to include("\\x1b", "\\x07", "\\x0a")
        expect(hint).not_to include("\e", "\nsaboteur: warning")
      end
    end

    it "escapes control characters in a hostile BUNDLE_GEMFILE value (Pod 1 security)" do
      with_root("Appraisals" => "appraise \"a\" do\nend\n") do |dir|
        hint = described_class.appraisal(dir, env: { "BUNDLE_GEMFILE" => "\e[2Jelsewhere.gemfile" })
        expect(hint).to include("points outside gemfiles/ (\\x1b[2Jelsewhere.gemfile)")
        expect(hint).not_to include("\e")
      end
    end

    it "survives a gemfile name that is not valid UTF-8 (Pod 1 security)" do
      Dir.mktmpdir do |dir|
        Dir.mkdir(File.join(dir, "gemfiles"))
        write_named(File.join(dir, "gemfiles"), "bad\xFFname.gemfile".b)
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to include("bad?name.gemfile")
      end
    end

    it "escapes C1 control characters in gemfile names (Pod 1 security)" do
      Dir.mktmpdir do |dir|
        Dir.mkdir(File.join(dir, "gemfiles"))
        name = "c1#{[0xC2, 0x85].pack('C*')}name.gemfile"
        write_named(File.join(dir, "gemfiles"), name)
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to include("c1\\x85name.gemfile")
        expect(hint).not_to include(name)
      end
    end

    it "lists all gemfiles without a suffix when there are exactly five" do
      files = (0..4).to_h { |i| ["gemfiles/g#{i}.gemfile", ""] }
      with_root(files) do |dir|
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to eq(
          "Appraisal gemfiles found (gemfiles/g0.gemfile, gemfiles/g1.gemfile, gemfiles/g2.gemfile, " \
          "gemfiles/g3.gemfile, gemfiles/g4.gemfile) but BUNDLE_GEMFILE is not set: run " \
          "`BUNDLE_GEMFILE=gemfiles/<name>.gemfile bundle exec saboteur run` or " \
          "`bundle exec appraisal <name> saboteur run`"
        )
      end
    end

    it "caps the list at five with a +1 more suffix when there are exactly six" do
      files = (0..5).to_h { |i| ["gemfiles/g#{i}.gemfile", ""] }
      with_root(files) do |dir|
        hint = described_class.appraisal(dir, env: {})
        expect(hint).to eq(
          "Appraisal gemfiles found (gemfiles/g0.gemfile, gemfiles/g1.gemfile, gemfiles/g2.gemfile, " \
          "gemfiles/g3.gemfile, gemfiles/g4.gemfile, +1 more) but BUNDLE_GEMFILE is not set: run " \
          "`BUNDLE_GEMFILE=gemfiles/<name>.gemfile bundle exec saboteur run` or " \
          "`bundle exec appraisal <name> saboteur run`"
        )
      end
    end

    it "treats a sibling directory sharing the gemfiles prefix as outside (#609)" do
      with_root(files) do |dir|
        hint = described_class.appraisal(dir, env: { "BUNDLE_GEMFILE" => "gemfiles_extra/x.gemfile" })
        expect(hint).to include("points outside gemfiles/ (gemfiles_extra/x.gemfile)")
      end
    end

    it "stays quiet when BUNDLE_GEMFILE is under gemfiles/ and without appraisal files" do
      with_root(files) do |dir|
        expect(described_class.appraisal(dir, env: { "BUNDLE_GEMFILE" => "gemfiles/rails_7_2.gemfile" })).to be_nil
      end
      with_root("lib/x.rb" => "x = 1\n") do |dir|
        expect(described_class.appraisal(dir, env: {})).to be_nil
      end
    end
  end
end
