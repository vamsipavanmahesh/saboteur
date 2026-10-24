#!/usr/bin/env python3
"""admit.py: strict admission of a downloaded run artifact (untrusted data; nothing in it is executed).
  admit.py structure <dir> <mode doctor|map> <era_or_-> <run_id> <wf_sha> <recipe_pin_file> <doctor_head> <map_head_or_->
  admit.py compat    <dir> <doctor|map> <this_out_dir> <ruby_v>
Exit 0 = admitted. Any missing, null, empty, wrong-typed or unexpected value is a block."""
import json, os, re, stat, sys

HEX64 = re.compile(r"\A[0-9a-f]{64}\Z"); HEX40 = re.compile(r"\A[0-9a-f]{40}\Z")
NAME = re.compile(r"\A[A-Za-z0-9._@=+,-]+\Z")
DOCTOR_REQUIRED = {"DOCTOR-VERDICT.txt", "doctor-meta.json", "doctor-raw.log", "prep.log", "job-start.txt", "recipe-pin.txt", "MANIFEST.sha256", "deps/expected-identity.json"}
MAP_REQUIRED = {"map-meta.json", "map-head-sha.txt", "map-era.txt", "TRIPLE.sha256", "RECEIPTS.txt", "job-start.txt", "recipe-pin.txt", "MANIFEST.sha256", "deps/expected-identity.json", "deps/1-Gemfile.lock.original", "deps/3-Gemfile.lock.installed", "deps/config.saboteur.rb", "deps/1-Gemfile.original", "prep.log"}

CACHE_NAMES = r'(coverage-[0-9a-f]{64}\.json|inputs-[0-9a-f]{64}\.json|whole-suite-map-v2|coverage-[0-9a-f]{64}-part-[0-9]+-of-[0-9]+\.json|preview\.json|coverage-build\.log|coverage-build-[0-9]+\.log|internal-error\.log|results\.json|manifest\.json|report\.json|baseline-[0-9]+\.log|baseline-[0-9]+-part-[0-9]+\.log|logs/[A-Za-z0-9_.-]+\.log|baseline-evidence/[A-Za-z0-9_.-]+\.json)'
TOP = {"DOCTOR-VERDICT.txt", "MAP-RECEIPT.txt", "METHOD.txt", "QUARANTINED.txt", "RECEIPTS.txt", "TRIPLE.sha256", "apt-versions.txt", "apt.log", "assets-meta.json",
       "bundle-install.log", "db-reset-meta.json", "dbassets.log", "doctor-meta.json", "doctor-raw.log", "doctor.log", "env-identity.txt", "env.env", "gem-fetch.log",
       "job-start.txt", "map-era.txt", "map-head-sha.txt", "map-meta.json", "map-report.json", "map.log", "map.log.raw", "pointer-receipt-after.txt", "pointer-receipt-before.txt",
       "postgres-identity.err", "postgres-identity.txt", "prep.log", "producer-job-start.txt", "producer-map-meta.json", "producer-recipe-pin.txt", "recipe-pin.txt",
       "replay-meta.json", "replay-raw.log", "replay.log", "report.html", "report.json", "service-image-identity.txt", "snapshot-drift.txt", "MANIFEST.sha256",
       "artifact-receipts.txt", "map-saboteur-unknown.txt", "replay-saboteur-unknown.txt"} | {"provenance-%s.json" % n for n in ()}
ALLOWED = [re.compile(p) for p in (
    r"\Aprovenance-\d+\.json\Z",
    r"\Adeps/(1-Gemfile\.lock\.original|1-Gemfile\.original|2-Gemfile\.lock\.patched-preinstall|2-Gemfile\.patched|3-Gemfile\.lock\.installed|bundle-list\.txt|cache-sha256\.txt|config\.saboteur\.rb|expected-identity\.json|lock-additions-vs-original\.diff|locked-gem-files\.txt)\Z",
    r"\Adeps/(installed|payload)-[A-Za-z0-9_.-]+-diff\.txt\Z",
    r"\Atriple/(coverage-[0-9a-f]{64}\.json|inputs-[0-9a-f]{64}\.json|whole-suite-map-v2)\Z",
    r"\A(map|replay)-saboteur-dir/" + CACHE_NAMES + r"\Z")]

def allowed(rel):
    return rel in TOP or any(r.match(rel) for r in ALLOWED)

def die(m):
    print("ADMISSION_BLOCK: " + m); sys.exit(1)

def files(d):
    out = set()
    for root, dirs, fs in os.walk(d, followlinks=False):
        for n in dirs + fs:
            p = os.path.join(root, n); rel = os.path.relpath(p, d)
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
                die("non-regular member " + rel)
            if not all(NAME.match(x) and not x.startswith(".") for x in rel.split(os.sep)):
                die("unsafe member name " + rel)
            if stat.S_ISREG(st.st_mode):
                out.add(rel)
    if len(out) > 5000: die("too many members")
    return out

def jload(p):
    try: return json.load(open(p))
    except Exception as e: die("%s is not valid JSON: %s" % (p, type(e).__name__))

def manifest_check(d, present):
    import hashlib
    listed = {}; seen = []
    for ln in open(os.path.join(d, "MANIFEST.sha256")).read().splitlines():
        m = re.match(r"\A([0-9a-f]{64})  \./(.+)\Z", ln)
        if not m: die("malformed manifest line")
        seen.append(m.group(2)); listed[m.group(2)] = m.group(1)
        if ".." in m.group(2).split("/") or m.group(2).startswith("/"): die("manifest path traversal")
    if len(seen) != len(listed): die("duplicate manifest entries")
    if set(listed) != present - {"MANIFEST.sha256"}:
        die("manifest does not cover exactly the artifact members (extra: %s, missing: %s)" % (sorted(present - {"MANIFEST.sha256"} - set(listed))[:3], sorted(set(listed) - present)[:3]))
    for rel, h in listed.items():
        if os.path.getsize(os.path.join(d, rel)) > 500 * 1024 * 1024: die("member too large " + rel)
        if hashlib.sha256(open(os.path.join(d, rel), "rb").read()).hexdigest() != h: die("hash mismatch " + rel)

def identity(p):
    i = jload(p)
    if not isinstance(i, dict) or not {"root", "settings", "runtime"} <= set(i): die("identity lacks root/settings/runtime")
    for k in ("root", "settings", "runtime"):
        if not (isinstance(i[k], str) and HEX64.match(i[k])): die("identity %s is not a 64-hex string" % k)
    return i

def structure(d, mode, era, rid, wsha, pinfile, dhead, mhead, drid="-"):
    present = files(d)
    req = DOCTOR_REQUIRED if mode == "doctor" else MAP_REQUIRED
    if req - present: die("missing members %s" % sorted(req - present))
    bad = sorted(x for x in present if not allowed(x))
    if bad: die("members outside the known artifact allowlist: %s" % bad[:5])
    if sum(os.path.getsize(os.path.join(d, x)) for x in present) > 2 * 1024 ** 3: die("artifact total size over 2 GiB")
    manifest_check(d, present)
    js = open(os.path.join(d, "job-start.txt")).read().splitlines()
    if len(js) != 3: die("job-start shape")
    m1 = re.match(r"\Amode=(\w+) era=(\S*) pr=(\S*) doctor_run_id=(\S*) map_run_id=(\S*)\Z", js[0])
    m2 = re.match(r"\Arun_id=(\d+) attempt=(\d+) workflow_sha=([0-9a-f]{40})\Z", js[1])
    if not (m1 and m2 and re.match(r"\Ajob_t0_epoch=\d+\Z", js[2])): die("job-start fields")
    if mode == "map" and m1.group(4) != drid: die("map job-start doctor_run_id is not the selected doctor run")
    if m1.group(1) != mode or (era != "-" and m1.group(2) != era): die("job-start mode/era")
    if m2.group(1) != rid or m2.group(2) != "1" or m2.group(3) != wsha: die("job-start run/attempt/workflow sha")
    pin = open(os.path.join(d, "recipe-pin.txt")).read()
    if not re.match(r"\Arecipe_commit=[0-9a-f]{40} recipe_tree=[0-9a-f]{40}\n?\Z", pin): die("recipe-pin shape (blank or malformed)")
    if pin != open(pinfile).read(): die("artifact ran a different recipe commit/tree")
    identity(os.path.join(d, "deps/expected-identity.json"))
    if mode == "doctor":
        meta = jload(os.path.join(d, "doctor-meta.json"))
        if not (isinstance(meta, dict) and meta.get("exit_code") == 0 and type(meta["exit_code"]) is int and meta.get("raw_returncode") == 0
                and meta.get("signal") is None and meta.get("error") is None and meta.get("stopped_by") is None
                and meta.get("cwd") == "/opt/he-app" and meta.get("boundary") == {"state": "none"}):
            die("doctor-meta is not a clean exit 0 (exit_code/raw_returncode/signal/error/stopped_by/cwd/boundary)")
        if not str(meta.get("command", "")).startswith('bash -c bundle exec saboteur doctor --suite > "$0" 2>&1 '): die("doctor command differs")
        if not re.match(r"\ADOCTOR_VERDICT=PASS \(one invocation, two internal passes, tree %s\)\n?\Z" % re.escape(dhead), open(os.path.join(d, "DOCTOR-VERDICT.txt")).read()):
            die("verdict is not PASS at the exact doctor head " + dhead)
        raw = open(os.path.join(d, "doctor-raw.log"), errors="replace").read().splitlines()
        if sum(1 for l in raw if re.match(r"\ABaseline: \d+ tests passed twice in the same order with seed", l)) != 1: die("raw log lacks exactly one native two-pass success line")
        if not re.search(r"^ruby ", open(os.path.join(d, "prep.log")).read(), re.M): die("prep.log lacks ruby identity")
    else:
        if open(os.path.join(d, "map-head-sha.txt")).read().strip() != mhead or open(os.path.join(d, "map-era.txt")).read().strip() != era: die("map head/era mismatch")
        meta = jload(os.path.join(d, "map-meta.json"))
        if not isinstance(meta, dict): die("map-meta is not an object")
        if any(meta.get(k) not in (None, False) for k in ("stopped_by", "killed_after_grace", "group_killed_on_exception", "orphan_cleanup_error", "error")):
            die("map-meta records a stop, kill or error")
        # the boundary stop is SIGINT: the child either handles it (exit 130, signal null) or dies of it (raw -2, signal 2); both normalize to 130
        ok_exit = type(meta.get("exit_code")) is int and meta["exit_code"] == 130 and (
            (meta.get("signal") is None and meta.get("raw_returncode") == 130) or (meta.get("signal") == 2 and meta.get("raw_returncode") == -2))
        b = meta.get("boundary")
        ok_b = isinstance(b, dict) and b.get("state") == "sent" and isinstance(b.get("pointer_key"), str) and HEX64.match(b["pointer_key"]) \
            and isinstance(b.get("sha256"), dict) and len(b["sha256"]) == 3 and all(isinstance(v, str) and HEX64.match(v) for v in b["sha256"].values())
        if not (ok_exit and ok_b and meta.get("cwd") == "/opt/he-app"):
            die("map-meta is not the validated boundary stop (exit 130 via SIGINT, boundary sent with 64-hex key and 3 hashes, cwd /opt/he-app)")
        if not str(meta.get("command", "")).startswith("bundle exec saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose --json "):
            die("map command differs from the historical command")
    print("PROVENANCE_CONTENT_OK %s mode=%s era=%s run=%s attempt=1" % (d, mode, era, rid))

def compat(d, mode, out, rubyv):
    mine = identity(os.path.join(out, "deps/expected-identity.json")); theirs = identity(os.path.join(d, "deps/expected-identity.json"))
    for k in ("root", "settings", "runtime"):
        if mine[k] != theirs[k]: die("%s identity differs from this job" % k)
    m = re.search(r"^ruby .+$", open(os.path.join(d, "prep.log")).read(), re.M)
    if not (rubyv.strip() and m and m.group(0).strip() == rubyv.strip()): die("different Ruby")
    print("ADMISSION_COMPAT_OK mode=%s identity+ruby equal" % mode)

if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "structure" and len(a) in (9, 10): structure(*a[1:])
    elif a and a[0] == "compat" and len(a) == 5: compat(*a[1:])
    else: die("usage")
