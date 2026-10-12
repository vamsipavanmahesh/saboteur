#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "digest"
require_relative "../../../lib/saboteur"
require_relative "matcher"

root = File.realpath(ARGV.fetch(0))
matcher = PatternEquivalence::Matcher.new
files = Dir.glob("lib/**/*.rb", base: root).sort
summary = { root: root, ruby: RUBY_DESCRIPTION, files: files.size, subjects: 0, generated: 0,
            parse_failures: [], matches: [], duplicates: 0, invalid: 0 }
files.each do |relative|
  found = Saboteur::SubjectFinder.new.call(File.join(root, relative))
  summary[:parse_failures] << relative if found.errors.any?
  found.subjects.each do |subject|
    summary[:subjects] += 1
    seen = {}
    Saboteur::MutationSource::Builtin.new.mutations_for(subject).each do |mutation|
      summary[:generated] += 1
      text = subject.apply(mutation.edits)
      unless Prism.parse(text).success?
        summary[:invalid] += 1
        next
      end
      if seen[text]
        summary[:duplicates] += 1
        next
      end
      seen[text] = true
      pattern = matcher.classify(subject, mutation)
      next unless pattern

      summary[:matches] << { file: relative, subject: subject.id, pattern: pattern, operator: mutation.operator,
                             original: subject.source, changed: text,
                             digest: mutation.digest(subject_start: subject.start_byte,
                                                     original_source: subject.file_source) }
    end
  end
end
puts JSON.pretty_generate(summary)
