#!/usr/bin/env python3
"""Run one command as an owned child, record receipts, optionally stop it at a verified map boundary.

usage: measure3.py --meta FILE [--cwd DIR] [--watch-dir DIR --attempt-start EPOCH --watch-deadline S]
                   [--poll S] -- command...

- The child is a direct Popen of the command: its PID is the one that is signalled, never a pgrep result.
- SIGINT is reset to the default action in the child, so a parent that inherited SIG_IGN cannot make
  the child ignore the boundary stop.
- Meta is written in a finally block (also when spawning fails). It records realtime and monotonic
  clocks, pid, /proc start ticks, the raw return code, the signal if any, and a normalized exit code
  (128+signal for a signal death). It always exits with the normalized code (255 on spawn failure).
- Boundary stop (map only): the watch logic of the reviewed watch4 script, in Python: coverage file,
  inputs file bound to the same key, pointer file bound to that key, all three modified after the
  attempt start, sizes stable across 12 s, coverage parses as JSON, pid + start ticks + cmdline
  re-verified before SIGINT. Result is recorded in meta as boundary={sent|failed|none, ...}.
"""
import argparse, hashlib, re, glob, json, os, resource, signal, subprocess, sys, time


def ticks(pid):
    try:
        return open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[19]
    except Exception:
        return None


def cmdline(pid):
    try:
        return open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf8", "replace")
    except Exception:
        return ""


def verify_pid(pid, start_ticks):
    return ticks(pid) == start_ticks


def verify(pid, start_ticks):
    return ticks(pid) == start_ticks and "saboteur run" in cmdline(pid)


HEX64 = re.compile(r"\A[0-9a-f]{64}\Z")
COVERAGE_FORMAT = 11   # saboteur 0.12.3 Selection::CoverageMap::FORMAT
INPUTS_FORMAT = 2      # saboteur 0.12.3 CoverageInputsSnapshot::FORMAT
INPUT_KEYS = sorted(["files", "format", "map_digest", "map_key", "root", "runtime", "seed", "settings"])


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_pair(cov, inp, ptr, ckey, expect_root=None, expect_seed=None, expect_runtime=None, expect_settings=None):
    """Native-format checks of the map/inputs/pointer triple. Returns None when valid, else a reason."""
    if not HEX64.match(ckey):
        return "key is not 64 lowercase hex"
    if os.path.basename(cov) != f"coverage-{ckey}.json" or os.path.basename(inp) != f"inputs-{ckey}.json":
        return "file names do not carry the key"
    for f in (cov, inp, ptr):
        if os.path.islink(f) or not os.path.isfile(f):
            return f"{os.path.basename(f)} is not a regular file"
    if open(ptr).read().strip() != ckey:
        return "pointer content differs from the key"
    try:
        c = json.load(open(cov))
        i = json.load(open(inp))
    except Exception as e:
        return f"unreadable json: {e}"
    if not isinstance(c, dict) or c.get("format") != COVERAGE_FORMAT:
        return "coverage format mismatch"
    t = c.get("tests")
    if not (isinstance(t, list) and t and all(isinstance(x, str) and x for x in t)):
        return "coverage has no tests"
    if not (isinstance(c.get("lines"), dict) and c["lines"]):
        return "coverage has no line data"
    if not isinstance(i, dict) or sorted(i.keys()) != INPUT_KEYS or i.get("format") != INPUTS_FORMAT:
        return "inputs schema mismatch"
    for k in ("runtime", "settings", "map_digest", "root"):
        if not (isinstance(i.get(k), str) and HEX64.match(i[k])):
            return f"inputs {k} is not 64 hex"
    if i.get("map_key") != ckey:
        return "inputs map_key differs from the key"
    if i["map_digest"] != sha256_file(cov):
        return "inputs map_digest does not match the coverage file bytes"
    if not isinstance(i.get("files"), dict) or not i["files"]:
        return "inputs files empty"
    if not (isinstance(i.get("seed"), int) and 0 <= i["seed"] <= 2**32 - 1):
        return "inputs seed invalid"
    if expect_root is not None and i["root"] != hashlib.sha256(expect_root.encode()).hexdigest():
        return "inputs root digest is not this app root"
    if expect_seed is not None and i["seed"] != expect_seed:
        return "inputs seed is not the expected seed"
    if expect_runtime is not None and i["runtime"] != expect_runtime:
        return "inputs runtime digest is not the setup-time native runtime identity"
    if expect_settings is not None and i["settings"] != expect_settings:
        return "inputs settings digest is not the setup-time native cache-input digest"
    return None


def check_boundary(d, astart):
    ptr = os.path.join(d, "whole-suite-map-v2")
    if not os.path.isfile(ptr):
        return None
    ckey = open(ptr).read().strip()
    cov = os.path.join(d, f"coverage-{ckey}.json")
    inp = os.path.join(d, f"inputs-{ckey}.json")
    if not (os.path.isfile(cov) and os.path.isfile(inp)):
        return None
    files = [cov, inp, ptr]
    if any(os.path.getmtime(f) < astart for f in files):
        return None
    return files, ckey


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meta", required=True)
    ap.add_argument("--cwd")
    ap.add_argument("--watch-dir")
    ap.add_argument("--attempt-start", type=float, default=0)
    ap.add_argument("--watch-deadline", type=float, default=3300)
    ap.add_argument("--expect-root", default=None, help="canonical app root; inputs.root must equal sha256 of it")
    ap.add_argument("--expect-seed", type=int, default=None)
    ap.add_argument("--expect-identity-file", default=None, help="JSON with runtime and settings digests computed by the pinned tool's own constants at setup")
    ap.add_argument("--poll", type=float, default=20)
    ap.add_argument("--timeout", type=float, default=0, help="hard limit in seconds for any command: SIGINT, then SIGKILL after 60 s")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    exp_rt = exp_st = None
    if a.expect_identity_file:
        ident = json.load(open(a.expect_identity_file))
        exp_rt, exp_st = ident["runtime"], ident["settings"]
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    meta = {"command": " ".join(cmd), "cwd": a.cwd or os.getcwd(), "boundary": {"state": "none"},
            "exit_code": None, "raw_returncode": None, "signal": None, "error": None}
    meta["started_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    meta["realtime_start"], meta["monotonic_start"] = time.time(), time.monotonic()
    norm = 255
    try:
        try:
            p = subprocess.Popen(cmd, cwd=a.cwd, start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
        except Exception as e:  # spawn failure still leaves a receipt
            meta["error"] = f"spawn failed: {type(e).__name__}: {e}"
            return 255
        meta["pid"] = p.pid
        meta["start_ticks"] = ticks(p.pid)
        meta["sigint_disposition_in_parent"] = "ignored" if signal.getsignal(signal.SIGINT) == signal.SIG_IGN else "default-or-handler"
        t_start = time.monotonic()
        watch_until = t_start + a.watch_deadline
        hard_until = t_start + a.timeout if a.timeout else None
        sent_int_at = None
        while p.poll() is None:
            time.sleep(a.poll)
            if p.poll() is not None:
                break
            now = time.monotonic()
            # grace: SIGKILL the owned child if it ignores the stop for 60 s
            if sent_int_at is not None:
                if now - sent_int_at > 60:
                    try:
                        os.killpg(p.pid, signal.SIGKILL)
                        meta["killed_after_grace"] = True
                    except Exception:
                        pass
                continue
            # hard timeout (all commands) and watch deadline without a boundary (map)
            reason = None
            if hard_until and now > hard_until:
                reason = "timeout"
            elif a.watch_dir and meta["boundary"]["state"] == "none" and now > watch_until:
                reason = "watch-deadline-no-boundary"
            if reason:
                if verify_pid(p.pid, meta["start_ticks"]):
                    try:
                        os.kill(p.pid, signal.SIGINT)
                    except Exception:
                        pass
                    sent_int_at = now
                    meta["stopped_by"] = reason
                continue
            if not a.watch_dir or meta["boundary"]["state"] != "none":
                continue
            res = check_boundary(a.watch_dir, a.attempt_start)
            if not res:
                continue
            files, ckey = res
            s1 = [os.path.getsize(f) for f in files]
            time.sleep(12 if a.poll >= 5 else 0.5)
            if p.poll() is not None:
                break
            if s1 != [os.path.getsize(f) for f in files]:
                continue
            reason_bad = validate_pair(files[0], files[1], files[2], ckey, a.expect_root, a.expect_seed, exp_rt, exp_st)
            if reason_bad:
                meta["boundary_last_rejection"] = reason_bad
                continue
            if not verify(p.pid, meta["start_ticks"]):
                continue
            info = {"coverage": os.path.basename(files[0]), "inputs": os.path.basename(files[1]), "pointer_key": ckey,
                    "pid": p.pid, "start_ticks": meta["start_ticks"], "attempt_start": a.attempt_start,
                    "realtime": time.time(), "monotonic": time.monotonic()}
            # re-read the pointer and re-hash the triple right before the stop, so a swapped pointer is not signalled as the validated pair
            hashes = {os.path.basename(f): sha256_file(f) for f in files}
            if open(files[2]).read().strip() != ckey or validate_pair(files[0], files[1], files[2], ckey, a.expect_root, a.expect_seed, exp_rt, exp_st):
                meta["boundary_last_rejection"] = "pointer or pair changed after validation"
                continue
            info["sha256"] = hashes
            try:
                os.kill(p.pid, signal.SIGINT)
                meta["boundary"] = {"state": "sent", **info}
                sent_int_at = time.monotonic()
            except Exception as e:
                meta["boundary"] = {"state": "failed", "error": str(e), **info}
        rc = p.wait()
        # leader gone does not mean the tree is gone: reap anything left in the owned group
        try:
            os.killpg(p.pid, 0)
            os.killpg(p.pid, signal.SIGKILL)
            meta["orphans_killed_after_leader_exit"] = True
        except ProcessLookupError:
            pass
        except Exception as e:
            meta["orphan_cleanup_error"] = str(e)
        meta["raw_returncode"] = rc
        if rc < 0:
            meta["signal"] = -rc
            norm = 128 - rc
        else:
            norm = rc
        return norm
    except BaseException as e:
        meta["error"] = f"watcher exception: {type(e).__name__}: {e}"
        try:
            os.killpg(p.pid, signal.SIGKILL)
            meta["group_killed_on_exception"] = True
            p.wait(timeout=30)
        except Exception:
            pass
        norm = 254
    finally:
        meta["realtime_end"], meta["monotonic_end"] = time.time(), time.monotonic()
        meta["ended_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        meta["wall_seconds_monotonic"] = round(meta["monotonic_end"] - meta["monotonic_start"], 3)
        meta["wall_seconds_realtime"] = round(meta["realtime_end"] - meta["realtime_start"], 3)
        if meta.get("stopped_by"):
            meta["raw_normalized_exit"] = norm
            norm = 124   # timeout/deadline is never success, whatever the child did on its stop signal
        meta["exit_code"] = norm
        meta["peak_rss_kb"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        json.dump(meta, open(a.meta, "w"), indent=2)
        print(json.dumps(meta))
        return norm


if __name__ == "__main__":
    sys.exit(main())
