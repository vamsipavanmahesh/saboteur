#!/usr/bin/env ruby
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

def assert(value, message)
  abort message unless value
end
Dir.mktmpdir do |dir|
  FileUtils.cp_r(File.expand_path('..', __dir__), File.join(dir, 'field'))
  root = File.join(dir, 'field')
  app = File.join(root, 'apps/lobsters')
  report = { 'files' => { 'app/a.rb' => { 'mutants' => [
    { 'id' => 'a', 'status' => 'Killed', 'killedBy' => ['0'], 'location' => { 'start' => { 'line' => 1 } } },
    { 'id' => 'b', 'status' => 'Survived', 'gapKind' => 'assertion_gap', 'location' => { 'start' => { 'line' => 2 } } }
  ] } }, 'testFiles' => { 'spec/a_spec.rb' => { 'tests' => [{ 'id' => '0', 'name' => './spec/a_spec.rb[1:1]' }] } }, 'saboteur' => { 'scores' => { 'all' => { 'score' => 50 } } } }
  %w[pr-one parallel-one].each do |scenario|
    path = File.join(app, 'reports', scenario);FileUtils.mkdir_p(path)
    File.write(File.join(path, 'report.json'), JSON.generate(report))
    File.write(File.join(path, 'measurement.json'), JSON.generate({ 'kind' => scenario.start_with?('pr-') ? 'pr' : 'parallel', 'reference_scenario' => 'pr-one', 'wall_seconds' => 1.25, 'exit_code' => 1, 'status' => 'partly' }))
  end
  script = File.join(root, 'script/summarize.rb')
  output, status = Open3.capture2e(RbConfig.ruby, script, '--select')
  assert(status.success?, output)
  md = File.read(File.join(root, 'REPORT.md'))
  assert(md.include?('unknown'), 'missing data became measured')
  assert(md.include?('1.25'), 'wall time absent')
  diff = JSON.parse(File.read(File.join(app, 'verification/parallel-one-verdict-diff.json')))
  assert(diff['only_reference'].empty? && diff['only_compared'].empty?, 'equal reports differ')
  selection = File.read(File.join(app, 'verification/selected.json'))
  _, status = Open3.capture2e(RbConfig.ruby, script, '--select')
  assert(status.success?, 'repeat failed')
  assert(selection == File.read(File.join(app, 'verification/selected.json')), 'sample changed on repeat')
  parallel = File.join(app, 'reports/parallel-one/report.json')
  report['files']['app/a.rb']['mutants'][0]['status'] = 'Survived'
  File.write(parallel, JSON.generate(report))
  _, status = Open3.capture2e(RbConfig.ruby, script)
  assert(status.success?, 'changed report generation failed')
  diff = JSON.parse(File.read(File.join(app, 'verification/parallel-one-verdict-diff.json')))
  assert(diff['only_reference'].size == 1 && diff['only_compared'].size == 1, 'changed verdict omitted')
end
puts 'summarize fixture tests pass'
