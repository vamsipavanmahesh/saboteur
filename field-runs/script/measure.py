#!/usr/bin/env python3
"""Record a command without hiding failure. stdout/stderr stay in raw log."""
import argparse,datetime,json,pathlib,resource,subprocess,time,sys
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--log',required=True);p.add_argument('--kind',required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
cmd=a.command[1:] if a.command[:1]==['--'] else a.command
if not cmd: p.error('missing command after --')
pathlib.Path(a.log).parent.mkdir(parents=True,exist_ok=True)
pathlib.Path(a.output).parent.mkdir(parents=True,exist_ok=True)
spawned=False
start=datetime.datetime.now(datetime.timezone.utc).isoformat();t=time.monotonic()
with open(a.log,'wb') as stream:
 try: result=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT);code=result.returncode;spawned=True
 except OSError as e: stream.write(str(e).encode());code=127
measurement=dict(kind=a.kind,status='done' if code==0 else 'partly',argv=cmd,started_at=start,ended_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),wall_seconds=time.monotonic()-t,exit_code=code,peak_rss_kb=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss if spawned and sys.platform.startswith('linux') else None,evidence_paths=[a.log])
pathlib.Path(a.output).write_text(json.dumps(measurement,indent=2)+'\n')
raise SystemExit(code if code>=0 else 128-code)
