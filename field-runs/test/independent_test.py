#!/usr/bin/env python3
"""Synthetic-only contract probes. Nothing here is real app execution evidence."""
import copy,json,os,pathlib,shutil,subprocess,tempfile,unittest
SOURCE=pathlib.Path(__file__).resolve().parents[1]
RUBY=os.environ.get('RUBY','ruby')
class Contract(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name)
  shutil.copytree(SOURCE/'script',self.root/'script');(self.root/'findings.md').write_text('Synthetic fixture only.\n')
  self.app=self.root/'apps'/'synthetic';self.app.mkdir(parents=True)
  self.report={'schemaVersion':'2','files':{'app/a.rb':{'language':'ruby','source':'def a; 1; end','mutants':[{'id':'a','status':'Killed','killedBy':['0'],'mutatorName':'number','replacement':'0','location':{'start':{'line':1,'column':8},'end':{'line':1,'column':9}}},{'id':'b','status':'Survived','classification':'input_gap','kind':'boundary','gapKind':'boundary','valueDiffered':False,'location':{'start':{'line':2,'column':1}}}]}},'testFiles':{'spec/a_spec.rb':{'tests':[{'id':'0','name':'./spec/a_spec.rb[1:1]'}]}},'saboteur':{'scores':{'all':{'score':17.25,'assertion_share':11.5,'crash_share':5.75}}}}
 def tearDown(self):self.temp.cleanup()
 def run_script(self,*args,ok=True):
  p=subprocess.run([RUBY,str(self.root/'script/summarize.rb'),*args],text=True,capture_output=True)
  if ok:self.assertEqual(p.returncode,0,p.stdout+p.stderr)
  else:self.assertNotEqual(p.returncode,0,'invalid evidence silently accepted')
  return p
 def put(self,name='pr-one',kind='pr',report=True,**metrics):
  d=self.app/'reports'/name;d.mkdir(parents=True,exist_ok=True)
  (d/'measurement.json').write_text(json.dumps(dict(kind=kind,status='partly',**metrics)))
  if report is not False:(d/'report.json').write_text(json.dumps(self.report if report is True else report))
  return d
 def md(self):return (self.root/'REPORT.md').read_text()
 def diff(self):return json.loads((self.app/'verification'/'compared-verdict-diff.json').read_text())
 def pair(self,changed=None):
  self.put();other=copy.deepcopy(self.report)
  if changed:changed(other)
  self.put('compared','parallel',other,reference_scenario='pr-one');self.run_script();return self.diff()
 def test_missing(self):
  self.put(report=False);self.run_script();self.assertIn('| pr-one | unknown | unknown | unknown | unknown | unknown | unknown | unknown | unknown |',self.md());self.assertIn('Fake kills: unknown.',self.md())
 def test_status_counts_and_score(self):
  mutants=self.report['files']['app/a.rb']['mutants'];mutants[:]=[dict(id=str(i),status=s) for i,s in enumerate(['Killed','Survived','Timeout','RuntimeError','CompileError','NoCoverage','Ignored','Pending'])]
  self.put(wall_seconds=1.25,peak_rss_kb=123,exit_code=70);self.run_script();self.assertIn('| pr-one | unknown | 8 | 1 | 1 | 1 | 2 | 3 |',self.md());self.assertIn('17.25',self.md());self.assertIn('1.25 | 123 | 70',self.md())
 def test_empty_measured(self):
  self.report['files']={};self.put();self.run_script();self.assertIn('| pr-one | unknown | 0 | 0 | 0 | 0 | 0 | 0 |',self.md())
 def test_equal_diff(self):self.assertEqual(self.pair()['only_reference'],[])
 def test_test_id_renumber(self):
  def change(r):r['testFiles']['spec/a_spec.rb']['tests'][0]['id']='9';r['files']['app/a.rb']['mutants'][0]['killedBy']=['9']
  self.assertEqual(self.pair(change)['only_reference'],[])
 def test_changed_verdict(self):self.assertEqual(len(self.pair(lambda r:r['files']['app/a.rb']['mutants'][0].update(status='Survived'))['only_reference']),1)
 def test_changed_file(self):self.assertEqual(len(self.pair(lambda r:r['files'].update({'app/moved.rb':r['files'].pop('app/a.rb')}))['only_reference']),2)
 def test_changed_classification(self):self.assertEqual(len(self.pair(lambda r:r['files']['app/a.rb']['mutants'][1].update(classification='assertion_gap'))['only_reference']),1)
 def test_changed_observation(self):self.assertEqual(len(self.pair(lambda r:r['files']['app/a.rb']['mutants'][1].update(valueDiffered=None))['only_reference']),1)
 def test_changed_confirmation(self):self.assertEqual(len(self.pair(lambda r:r['files']['app/a.rb']['mutants'][1].update(confirmation='unconfirmed'))['only_reference']),1)
 def test_changed_kill_cause(self):self.assertEqual(len(self.pair(lambda r:r['files']['app/a.rb']['mutants'][0].update(statusReason='crash: timeout'))['only_reference']),1)
 def test_unknown_test_fails(self):
  self.report['files']['app/a.rb']['mutants'][0]['killedBy']=['missing'];self.put();self.put('compared','parallel',reference_scenario='pr-one');self.run_script(ok=False)
 def test_duplicate_mutants_fail(self):
  self.report['files']['app/a.rb']['mutants'].append(copy.deepcopy(self.report['files']['app/a.rb']['mutants'][0]));self.put();self.run_script('--select',ok=False)
 def test_duplicate_test_ids_fail(self):
  self.report['testFiles']['spec/a_spec.rb']['tests'].append({'id':'0','name':'different'});self.put();self.run_script(ok=False)
 def test_scenario_identity(self):
  self.put();self.put('pr-two');self.run_script('--select');s=json.loads((self.app/'verification/selected.json').read_text());self.assertEqual(len(s['survivors']),2);self.assertEqual(len(s['kills']),2)
 def test_no_selection_without_reports(self):
  self.run_script('--select');self.assertFalse((self.app/'verification/selected.json').exists())
 def test_seed_caps_and_preservation(self):
  self.report['files']['app/a.rb']['mutants']=[dict(id=f'{i:03}',status=('Survived' if i<40 else 'Killed')) for i in range(70)]
  self.put();self.run_script('--select');p=self.app/'verification/selected.json';before=p.read_bytes();s=json.loads(before);self.assertEqual(len(s['survivors']),25);self.assertEqual(len(s['kills']),10)
  expected=json.loads(subprocess.check_output([RUBY,'-rjson','-e','puts JSON.generate((40...70).map { |i| "%03d" % i }.shuffle(random: Random.new(20261023)).first(10))'],text=True));self.assertEqual([r['id'] for r in s['kills']],expected)
  self.run_script('--select');self.assertEqual(p.read_bytes(),before)
  self.report['files']['app/a.rb']['mutants'].append(dict(id='zzz',status='Killed'));self.put();self.run_script('--select',ok=False);self.assertEqual(p.read_bytes(),before)
 def test_csv_counts(self):
  self.put();(self.app/'triage.csv').write_text('scenario,mutant_id,file_line,classification,evidence_path\npr-one,b,app/a.rb:2,false survivor,proof.txt\n');(self.app/'kills.csv').write_text('scenario,mutant_id,file_line,cause,evidence_path,issue_url\npr-one,a,app/a.rb:1,DB/infrastructure error,proof.txt,\n');self.run_script();self.assertIn('| false survivor | 1 |',self.md());self.assertIn('Fake kills: 1.',self.md())
 def test_duplicate_csv_fails(self):
  self.put();(self.app/'kills.csv').write_text('scenario,mutant_id,file_line,cause,evidence_path\n'+('pr-one,a,app/a.rb:1,exception,proof.txt\n'*2));self.run_script(ok=False)
 def test_unknown_csv_class_fails(self):
  self.put();(self.app/'triage.csv').write_text('scenario,mutant_id,file_line,classification,evidence_path\npr-one,b,app/a.rb:2,looks good,proof.txt\n');self.run_script(ok=False)
 def test_foreign_csv_id_fails(self):
  self.put();(self.app/'kills.csv').write_text('scenario,mutant_id,file_line,cause,evidence_path\npr-one,nonexistent,app/a.rb:1,exception,proof.txt\n');self.run_script(ok=False)
 def test_header_only_csv_unknown(self):
  (self.app/'kills.csv').write_text('scenario,mutant_id,file_line,cause,evidence_path\n');self.run_script();self.assertIn('Fake kills: unknown.',self.md())
 def test_selection_missing_directory(self):
  self.put();self.run_script('--select');self.assertTrue((self.app/'verification/selected.json').exists())
 def test_baseline_present(self):
  logs=self.app/'logs';logs.mkdir();(logs/'baseline-rspec.json').write_text(json.dumps({'summary':{'example_count':7,'failure_count':2,'pending_count':1,'errors_outside_of_examples_count':3}}))
  self.run_script();self.assertIn('| 7 | 2 | 1 | 3 |',self.md())
 def test_baseline_missing(self):
  self.run_script();section=self.md().split('### Baseline example results')[1].split('### Per-PR raw results')[0];self.assertIn('| unknown | unknown | unknown | unknown |',section)
 def test_baseline_partial(self):
  logs=self.app/'logs';logs.mkdir();(logs/'baseline-rspec.json').write_text(json.dumps({'summary':{'example_count':0,'failure_count':0}}))
  self.run_script();self.assertIn('| 0 | 0 | unknown | unknown |',self.md())
 def test_app_findings_present(self):
  (self.app/'findings.md').write_text('Synthetic app finding.');self.run_script();self.assertIn('### App findings\n\nSynthetic app finding.',self.md())
 def test_app_findings_missing(self):
  self.run_script();self.assertIn('### App findings\n\nUnknown pending execution and verification.',self.md())
 def extra_evidence(self,path='apps/synthetic/logs/baseline-extra-rspec.json'):
  d=self.app/'logs';d.mkdir(exist_ok=True);(d/'baseline-extra-rspec.json').write_text(json.dumps({'summary':{'example_count':31,'failure_count':0,'pending_count':0,'errors_outside_of_examples_count':0}}))
  self.put('baseline-extra','baseline',report=False,wall_seconds=8,evidence_paths=[path])
 def test_multiple_baselines_primary(self):
  self.put('baseline','baseline',report=False,wall_seconds=213);self.extra_evidence();self.run_script();self.assertIn('| synthetic | unknown | unknown | unknown | 213 | unknown |',self.md());self.assertIn('| baseline-extra | 31 | 0 | 0 | 0 | 8 |',self.md())
 def test_additional_app_relative(self):
  self.put('baseline','baseline',report=False);self.extra_evidence('logs/baseline-extra-rspec.json');self.run_script();self.assertIn('| baseline-extra | 31 | 0 | 0 | 0 | 8 |',self.md())
 def test_additional_missing_unknown(self):
  self.put('baseline','baseline',report=False);self.put('baseline-extra','baseline',report=False,evidence_paths=['logs/missing-rspec.json']);self.run_script();self.assertIn('| baseline-extra | unknown | unknown | unknown | unknown | unknown |',self.md())
 def test_additional_ambiguous_rejected(self):
  self.put('baseline','baseline',report=False);self.extra_evidence('logs/baseline-extra-rspec.json');d=self.root/'logs';d.mkdir();(d/'baseline-extra-rspec.json').write_text('{}');self.run_script(ok=False)
 def test_baseline_fallback(self):
  self.put('legacy-baseline','baseline',report=False,wall_seconds=17);self.run_script();self.assertIn('| synthetic | unknown | unknown | unknown | 17 | unknown |',self.md())
 def test_determinism_kind(self):
  self.put();self.put('compared','determinism',reference_scenario='pr-one');self.run_script();self.assertEqual(self.diff()['only_reference'],[])
if __name__=='__main__':unittest.main(verbosity=2)
