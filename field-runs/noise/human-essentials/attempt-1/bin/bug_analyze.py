#!/usr/bin/env python3
"""bug_analyze.py <fix_head_sha> <pr_number> - fixed lines, blame, introducing commit/PR, eligibility.
Writes bugs/human-essentials-<fix_sha>/line-map.json + raws. Rule (frozen):
- fixed lines = '-' lines (old coordinates) of the fix diff in app//lib .rb files.
- blame on fix_parent for each fixed line (exact, no -w) -> introducing commit per line.
- introducing PR = oldest first-parent PR commit on main ancestry-path from introducing commit.
- skip reasons recorded, not filtered silently.
"""
import json, re, subprocess, sys, os

REPO = "/home/sandbox/human-essentials"
WINDOW_START = "2026-04-24T00:00:00+05:30"
fix_head, pr = sys.argv[1], sys.argv[2]
def git(*a, cwd=REPO):
    return subprocess.run(["git", "-C", cwd] + list(a), capture_output=True, text=True, check=True).stdout

fix_parent = git("rev-parse", f"{fix_head}^1").strip()
bugdir = f"/home/sandbox/field-run/bugs/human-essentials-{fix_head}"
os.makedirs(f"{bugdir}/raws", exist_ok=True)

diff = git("diff", f"{fix_parent}..{fix_head}", "--", "app", "lib")
open(f"{bugdir}/raws/fix-hunk.diff", "w").write(diff)

# parse hunks: old-coordinate '-' lines per file
fixed = {}  # path -> [old_lineno]
cur, old_ln = None, None
for line in diff.splitlines():
    m = re.match(r"^\+\+\+ b/(.*\.rb)$", line)
    if m: cur = m.group(1); continue
    h = re.match(r"^@@ -(\d+)(?:,\d+)? \+", line)
    if h: old_ln = int(h.group(1)); continue
    if cur is None or old_ln is None: continue
    if line.startswith("-") and not line.startswith("---"):
        fixed.setdefault(cur, []).append(old_ln); old_ln += 1
    elif line.startswith("+") or line.startswith("\\"):
        pass
    else:
        old_ln += 1

records, intro_commits = [], set()
for path, lines in fixed.items():
    for ln in lines:
        try:
            porc = git("blame", "--line-porcelain", "-L", f"{ln},{ln}", fix_parent, "--", path)
            sha = porc.split()[0]
            orig = re.search(r"^\t(.*)$", porc, re.M).group(1)
        except subprocess.CalledProcessError:
            sha, orig = None, None
        intro_commits.add(sha)
        cdate = git("log", "-1", "--format=%cI", sha).strip() if sha else None
        records.append({"file": path, "fix_parent_line": ln, "blame_commit": sha,
                        "committer_date": cdate, "content": orig})

intro_list = sorted(c for c in intro_commits if c)
result = {"fix_head": fix_head, "fix_parent": fix_parent, "pr": int(pr),
          "fixed_lines": records, "introducing_commits": intro_list, "skips": []}
open(f"{bugdir}/raws/blame-fixed-lines.json", "w").write(json.dumps(records, indent=1))

prs = {}
# PR resolution ONLY for window-eligible (young) commits; old commits skip by B2 age rule
# without PR mapping (skip reason complete, avoids O(history) walks).
young = []
for c in intro_list:
    cdate = git("log", "-1", "--format=%cI", c).strip()
    prs[c] = {"introducing_pr_sha": None, "introducing_pr": None, "committer_date": cdate,
              "older_than_6mo": cdate < WINDOW_START, "pr_resolution": "skipped-old" if cdate < WINDOW_START else "pending"}
    if cdate >= WINDOW_START: young.append(c)
for c in young:
    s = git("log", "-1", "--format=%s", c).strip()
    m = re.match(r"^Merge pull request #(\d+)", s) or re.search(r"\(#(\d+)\)\s*$", s)
    if m:
        prs[c].update(introducing_pr_sha=c, introducing_pr=int(m.group(1)), pr_resolution="self-mainline")
        continue
    log = git("log", "--ancestry-path", "--merges", "--format=%H%x1f%s", f"{c}..{fix_parent}")
    found = None
    for entry in reversed(log.strip().splitlines()):
        sha, subj = entry.split("\x1f")
        m = re.match(r"^Merge pull request #(\d+)", subj) or re.search(r"\(#(\d+)\)\s*$", subj)
        if m: found = (sha, int(m.group(1))); break
    if found: prs[c].update(introducing_pr_sha=found[0], introducing_pr=found[1], pr_resolution="ancestry-path-merge")
    else: prs[c]["pr_resolution"] = "no-pr-found"

result["introducing_prs"] = prs

# eligibility: age + ruby + db at introducing PR head (fallback: introducing commit)
for c, info in prs.items():
    chk = info["introducing_pr_sha"] or c
    cdate = git("log", "-1", "--format=%cI", c).strip()
    info["committer_date"] = cdate
    info["older_than_6mo"] = cdate < WINDOW_START
    try: info["ruby_version_at_head"] = git("show", f"{chk}:.ruby-version").strip()
    except subprocess.CalledProcessError: info["ruby_version_at_head"] = None
    try: info["db_adapter_at_head"] = "postgresql" if "postgresql" in git("show", f"{chk}:config/database.yml") else "OTHER"
    except subprocess.CalledProcessError: info["db_adapter_at_head"] = "UNKNOWN"

json.dump(result, open(f"{bugdir}/line-map.json", "w"), indent=1)
print(json.dumps({"fix": fix_head[:12], "fixed_line_count": len(records),
                  "introducing": prs}, indent=1))
