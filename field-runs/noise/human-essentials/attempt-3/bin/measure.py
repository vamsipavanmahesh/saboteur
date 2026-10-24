#!/usr/bin/env python3
# measure.py OUT_JSON CMD... - measured run + Lobsters-compatible measurement envelope.
# Env: KIND, BASE_SHA, HEAD_SHA, PR_URL, LOG_FILE (stdout+stderr tee'd here).
import json, os, resource, subprocess, sys, time, datetime
out_json = sys.argv[1]; cmd = sys.argv[2:]
log_file = os.environ.get("LOG_FILE")
started = datetime.datetime.now(datetime.timezone.utc).astimezone()
t0 = time.monotonic()
out = open(log_file, "ab") if log_file else None
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
for chunk in iter(lambda: p.stdout.read1(65536), b""):
    sys.stdout.buffer.write(chunk); sys.stdout.buffer.flush()
    if out: out.write(chunk); out.flush()
rc = p.wait()
wall = time.monotonic() - t0
ended = datetime.datetime.now(datetime.timezone.utc).astimezone()
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
line = f"MEASURED exit={rc} wall={wall:.2f}s rss_kb={rss}"
print(line)
if out: out.write((line + "\n").encode()); out.close()
env = {"kind": os.environ.get("KIND"), "status": None, "command": " ".join(cmd),
       "started_at": started.isoformat(), "ended_at": ended.isoformat(),
       "wall_seconds": round(wall, 2), "exit_code": rc, "peak_rss_kb": rss,
       "base_sha": os.environ.get("BASE_SHA"), "head_sha": os.environ.get("HEAD_SHA"),
       "pr_url": os.environ.get("PR_URL"), "saboteur_version": "0.12.3",
       "saboteur_sha": "6f87ccc98377bf0c23f3cf409006f0464c2aa67c", "evidence_paths": []}
json.dump(env, open(out_json, "w"), indent=1)
sys.exit(rc)
