#!/usr/bin/env python3
# usage: runmeasured.py <meta.json> -- <command...>
# runs command, records wall seconds, exit code, peak child RSS (ru_maxrss, KB)
import json, resource, subprocess, sys, time
meta_path = sys.argv[1]
assert sys.argv[2] == "--"
cmd = sys.argv[3:]
start = time.time()
start_iso = time.strftime("%Y-%m-%dT%H:%M:%S%z")
p = subprocess.run(cmd)
end = time.time()
end_iso = time.strftime("%Y-%m-%dT%H:%M:%S%z")
ru = resource.getrusage(resource.RUSAGE_CHILDREN)
meta = {"command": " ".join(cmd), "started_at": start_iso, "ended_at": end_iso,
        "wall_seconds": round(end - start, 3), "exit_code": p.returncode,
        "peak_rss_kb": ru.ru_maxrss}
with open(meta_path, "w") as f:
    json.dump(meta, f, indent=2)
print(json.dumps(meta))
sys.exit(p.returncode)
