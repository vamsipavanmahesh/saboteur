# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::TestCommandShape do
  # ruby executes only the FIRST script named on its command line; extra
  # .rb arguments become ARGV, so the rest of the suite silently never
  # runs and its mutants inflate the survivors (#611). One example per
  # case from the review table.
  describe ".multi_file_ruby?" do
    {
      # warns: one ruby handed several test files, through wrappers
      "ruby -Itest test/a_test.rb test/b_test.rb" => true,
      "bundle exec ruby -Itest a_test.rb b_test.rb" => true,
      "bundle exec -- ruby a_test.rb b_test.rb" => true,
      "RUBYOPT=-w ruby a_test.rb b_test.rb" => true,
      "bundle exec env FOO=1 ruby a_test.rb b_test.rb" => true,
      "env -i ruby a_test.rb b_test.rb" => true,
      "/usr/bin/env ruby a_test.rb b_test.rb" => true,
      "timeout 60 ruby a_test.rb b_test.rb" => true,
      "nice ruby a_test.rb b_test.rb" => true,
      "nice -n 5 ruby a_test.rb b_test.rb" => true,
      "time ruby a_test.rb b_test.rb" => true,
      "time -p ruby a_test.rb b_test.rb" => true,
      "ruby3.4 a_test.rb b_test.rb" => true,
      "ruby a_spec.rb b_spec.rb" => true,
      # quiet: a non-test script taking file arguments is a runner
      "ruby test/runner.rb a_test.rb b_test.rb" => false,
      "ruby a.rb b.rb" => false,
      # quiet: option operands are not scripts
      "ruby -r ./helper.rb test/a_test.rb" => false,
      "ruby -Itest -r./helper.rb a_test.rb" => false,
      "ruby -C test a_test.rb" => false,
      # quiet: -e carries the script; the files are the loader's business
      "ruby -e 'ARGV.each { |f| require_relative f }' a_test.rb b_test.rb" => false,
      "ruby -Itest -e 'ARGV.each { |f| require f }' a_test.rb b_test.rb" => false,
      "ruby -e 'puts 1' a_test.rb b_test.rb" => false,
      "ruby -rminitest/autorun -e 'ARGV.each { |f| load f }' a_test.rb b_test.rb" => false,
      # QA survivor pins: -e may be glued and --eval is a separate form.
      "ruby -eputs a_test.rb b_test.rb" => false,
      "ruby --eval puts a_test.rb b_test.rb" => false,
      "jruby a_test.rb b_test.rb" => false,
      # Wrapper operands must not become the executable or swallow ruby.
      "timeout -v 60 ruby a_test.rb b_test.rb" => true,
      "nice --adjustment 5 ruby a_test.rb b_test.rb" => true,
      "nice -n5 ruby a_test.rb b_test.rb" => true,
      "nice --adjustment=5 ruby a_test.rb b_test.rb" => true,
      "nice -5 ruby a_test.rb b_test.rb" => true,
      "env -u NAME ruby a_test.rb b_test.rb" => true,
      "env -C spec ruby a_test.rb b_test.rb" => true,
      "nice -n5x ruby a_test.rb b_test.rb" => true,
      "nice --adjustment= ruby a_test.rb b_test.rb" => true,
      "nice -12 ruby a_test.rb b_test.rb" => true,
      "nice prefix-n5 ruby a_test.rb b_test.rb" => false,
      "nice prefix--adjustment=5 ruby a_test.rb b_test.rb" => false,
      "nice prefix-5 ruby a_test.rb b_test.rb" => false,
      # quiet: redirections are shell syntax, not ruby operands
      "ruby a_test.rb > output.rb" => false,
      "ruby a_test.rb 2> errors.rb" => false,
      "ruby a_test.rb < input.rb" => false,
      "ruby a_test.rb >output.rb" => false,
      "ruby a_test.rb 2>errors.rb" => false,
      "ruby a_test.rb &> all.rb" => false,
      # warns: a redirect elsewhere leaves the extra test file in ARGV
      "ruby a_test.rb > log.txt b_test.rb" => true,
      # warns: a glued trailing separator keeps its head (b_test.rb;)
      "ruby a_test.rb b_test.rb;" => true,
      # warns: an unquoted ";" splits even glued to the next word (;ruby)
      "cd spec;ruby -Itest a_test.rb b_test.rb" => true,
      # quiet: glued ";" compound, each ruby named a single file
      "ruby a_test.rb;ruby b_test.rb" => false,
      # warns: a ";" inside a quoted filename is just a name, and ruby
      # still runs only the first script
      'ruby "a;b_test.rb" c_test.rb' => true,
      # quiet: shell compound forms run their rubies separately
      "ruby a_test.rb && ruby b_test.rb" => false,
      "ruby -Itest a_test.rb && ruby -Itest b_test.rb" => false,
      "ruby a_test.rb; ruby b_test.rb" => false,
      'for f in a_test.rb b_test.rb; do ruby -Itest "$f" || exit 1; done' => false,
      # quiet: framework multi-file forms, single file, non-ruby
      "bin/rails test test/a_test.rb test/b_test.rb" => false,
      "bundle exec rspec a_spec.rb b_spec.rb" => false,
      "ruby -Itest test/a_test.rb" => false,
      "make test" => false,
      # quiet: nested shell is a known false negative, by design
      "sh -c 'ruby a_test.rb b_test.rb'" => false
    }.each do |command, warns|
      it "#{warns ? 'warns on' : 'stays quiet for'} `#{command}`" do
        expect(described_class.multi_file_ruby?(command)).to be(warns)
      end
    end
  end
end
