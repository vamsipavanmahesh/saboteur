#!/usr/bin/env python3
"""Apply report-recorded edits in a disposable era checkout; record paired controls."""
import datetime,difflib,hashlib,json,os,pathlib,subprocess,time
ROOT=pathlib.Path('/tmp/kill2231');APP=ROOT/'app';OUT=ROOT/'evidence';OUT.mkdir(exist_ok=True)
report=json.loads((ROOT/'packet/canary-packet/report.json').read_text());tests={t['id']:t['name'] for group in report['testFiles'].values() for t in group['tests']}
ids=['de58186074f0256b','a40b6c227630d3c3','5ea32ddfa7071c31','46132a2113f3aa6c']
results=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def offset(text,pos):return sum(len(x) for x in text.splitlines(keepends=True)[:pos['line']-1])+pos['column']-1
for mid in ids:
 matches=[(f,m) for f,entry in report['files'].items() for m in entry['mutants'] if m['id']==mid];assert len(matches)==1
 file,m=matches[0];path=APP/file;original=path.read_bytes();text=original.decode();start=offset(text,m['location']['start']);end=offset(text,m['location']['end']);mutated=(text[:start]+m['replacement']+text[end:]).encode();d=OUT/mid;d.mkdir(exist_ok=True)
 (d/'report-mutant.json').write_text(json.dumps(m,indent=2)+'\n');(d/'applied.diff').write_text(''.join(difflib.unified_diff(text.splitlines(True),mutated.decode().splitlines(True),fromfile='a/'+file,tofile='b/'+file)))
 selected=[tests[t] for t in m['killedBy']];runs=[]
 try:
  for label,body in [('original',original),('mutant',mutated),('restored',original)]:
   path.write_bytes(body);cmd=[os.environ['RUBY_HOME']+'/bin/ruby',os.environ['RUBY_HOME']+'/bin/bundle','exec','rspec',*selected,'--seed','20261024','--format','json','--out',str(d/(label+'.json'))];started=datetime.datetime.now(datetime.timezone.utc).isoformat();t=time.monotonic()
   with (d/(label+'.log')).open('wb') as log:p=subprocess.run(cmd,cwd=APP,stdout=log,stderr=subprocess.STDOUT)
   raw=json.loads((d/(label+'.json')).read_text());runs.append(dict(label=label,argv=cmd,started_at=started,wall_seconds=time.monotonic()-t,exit_code=p.returncode,file_sha256=sha(path.read_bytes()),summary=raw['summary'],examples=[{k:e.get(k) for k in ['id','full_description','status','exception']} for e in raw['examples']]))
 finally:
  path.write_bytes(original)
 receipt=dict(id=mid,source_file=file,tests=selected,original_sha256=sha(original),mutant_sha256=sha(mutated),restored_sha256=sha(path.read_bytes()),runs=runs)
 (d/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');assert sha(path.read_bytes())==sha(original)
 assert runs[0]['exit_code']==0 and runs[0]['summary']['example_count']==1 and runs[0]['summary']['failure_count']==0
 assert runs[1]['exit_code']==1 and runs[1]['summary']['example_count']==1 and runs[1]['summary']['failure_count']==1
 assert runs[2]['exit_code']==0 and runs[2]['summary']['example_count']==1 and runs[2]['summary']['failure_count']==0
 results.append(receipt);print(mid,[(r['label'],r['exit_code']) for r in runs],flush=True)
(OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n')
