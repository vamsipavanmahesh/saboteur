require 'json'
require 'saboteur'
require 'saboteur/subject_finder'
require 'saboteur/mutation_source/builtin'
file = File.expand_path('app/controllers/stories_controller.rb')
subject = Saboteur::SubjectFinder.new.call(file).subjects.find { |s| s.id == 'StoriesController#show' }
source = File.binread(file)
mutations = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
report = JSON.parse(File.read('/tmp/triage2157/packet/reports/pr2157-replay-c1r/report.json'))
ids = report.fetch('files').values.flat_map { |e| e.fetch('mutants') }.map { |m| m.fetch('id') }
selected = mutations.filter_map do |m|
  id = m.digest(subject_start: subject.start_byte, original_source: source)
  next unless ids.include?(id)
  {id: id, operator: m.operator, edits: m.edits.map { |e| {start_byte:e.start_byte,end_byte:e.end_byte,replacement:e.replacement,original:source.byteslice(e.start_byte...e.end_byte)} }}
end
abort "Missing mutations #{ids - selected.map { |s| s[:id] }}" unless (ids - selected.map { |s| s[:id] }).empty?
puts JSON.pretty_generate(selected)
