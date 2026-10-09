# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module ReportHelpers
  PERSON = <<~RUBY
    class Person
      def adult?; @age >= 18; end
    end
  RUBY

  def person_subject
    @person_subject ||= subjects_in(PERSON, name: "person.rb").first
  end

  def comparison_mutation(replacement: ">")
    at = person_subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: at, end_byte: at + 2,
                                              replacement:)
    Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator: "comparison", edits: [edit])
  end

  def result_for(status, replacement: ">", **)
    mutation = comparison_mutation(replacement:)
    Saboteur::MutantResult.new(subject: person_subject, mutation:, status:,
                               mutated_source: person_subject.apply(mutation.edits), **)
  end

  def report_of(*results, warnings: [])
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.25,
                         root: File.dirname(person_subject.file), warnings:)
  end
end

RSpec.configure { |config| config.include ReportHelpers }
