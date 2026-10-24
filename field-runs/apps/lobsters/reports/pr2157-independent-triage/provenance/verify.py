import pathlib,json,subprocess,hashlib,difflib,time,os,sys
R=pathlib.Path('/tmp/triage2157');A=R/'app';O=R/'evidence';O.mkdir(exist_ok=True)
r=json.load(open(R/'packet/reports/pr2157-replay-c1r/report.json'));tests={t['id']:t['name'] for f in r['testFiles'].values() for t in f['tests']};edits={e['id']:e for e in json.load(open(R/'exact-edits.json'))};source=A/'app/controllers/stories_controller.rb';orig=source.read_bytes()
new='spec/requests/independent_pr2157_meta_spec.rb'
def run(d,label,names):
 cmd=[os.environ['RUBY_HOME']+'/bin/ruby',os.environ['RUBY_HOME']+'/bin/bundle','exec','rspec',*names,'--seed','20261024','--format','json','--out',str(d/(label+'.json'))];t=time.monotonic()
 with (d/(label+'.log')).open('wb') as f:p=subprocess.run(cmd,cwd=A,stdout=f,stderr=subprocess.STDOUT)
 raw=json.load(open(d/(label+'.json')));return dict(label=label,argv=cmd,exit_code=p.returncode,wall_seconds=time.monotonic()-t,summary=raw['summary'],examples=[{k:e.get(k) for k in ['id','status','full_description','exception']} for e in raw['examples']])
for f,entry in r['files'].items():
 for m in entry['mutants']:
  if (m['status']=='Killed') != (sys.argv[1]=='kills'):continue
  mid=m['id'];d=O/mid
  if (d/'receipt.json').is_file():continue
  if len(sys.argv)>2 and mid!=sys.argv[2]:continue
  d.mkdir(exist_ok=True);mut=orig
  for e in sorted(edits[mid]['edits'],key=lambda x:x['start_byte'],reverse=True):
   assert orig[e['start_byte']:e['end_byte']].decode()==e['original'];mut=mut[:e['start_byte']]+e['replacement'].encode()+mut[e['end_byte']:]
  (d/'applied.diff').write_text(''.join(difflib.unified_diff(orig.decode().splitlines(True),mut.decode().splitlines(True),fromfile='a/'+f,tofile='b/'+f)))
  (d/'mutation.json').write_text(json.dumps(dict(report=m,actual_edits=edits[mid]),indent=2)+'\n');rs=[]
  try:
   if m['status']=='Killed':
    names=[tests[t] for t in m['killedBy']]
    for label,b in [('original',orig),('mutant',mut),('restored',orig)]:source.write_bytes(b);rs.append(run(d,label,names))
    assert [x['exit_code'] for x in rs]==[0,1,0]
   else:
    names=[tests[t] for t in m['executed']]
    source.write_bytes(orig);rs.append(run(d,'existing-original',names));source.write_bytes(mut);rs.append(run(d,'existing-mutant',names));assert [x['exit_code'] for x in rs]==[0,0]
    for label,b in [('new-original',orig),('new-mutant',mut),('new-restored',orig)]:source.write_bytes(b);rs.append(run(d,label,[new]))
    assert [x['exit_code'] for x in rs[-3:]]==[0,1,0]
  finally:source.write_bytes(orig)
  receipt=dict(id=mid,classification='genuine kill' if m['status']=='Killed' else 'real gap',original_sha256=hashlib.sha256(orig).hexdigest(),restored_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),runs=rs)
  (d/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(mid,[(x['label'],x['exit_code'],x['summary']['example_count']) for x in rs],flush=True)
