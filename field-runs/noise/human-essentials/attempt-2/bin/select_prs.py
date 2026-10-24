#!/usr/bin/env python3
"""Frozen selection for human-essentials field run, anchored 2026-10-24 08:11 IST.

Rules (frozen before inspection of results):
- FROZEN_HEAD: e5e69704fc49babacb2684bf846560dcb2e63988 (main tip at freeze).
- A merged PR = a first-parent commit of main whose subject matches
  'Merge pull request #N' OR ends with '(#N)' (squash merge).
- WINDOW: committer date >= 2026-04-24T00:00:00+05:30 (6 months before anchor).
- Noise list: most recent 15 PRs (any age) whose diff vs first parent touches
  app/**/*.rb or lib/**/*.rb.
- Bug-fix candidates: PRs inside the window matching any of:
    (a) subject contains 'fix' (case-insensitive substring),
    (b) subject/body contains a closing issue reference
        (fixes|closes|resolves) #N (case-insensitive),
    (c) diff adds lines to spec/** files AND changes app/**/*.rb or lib/**/*.rb.
  Ordered by merge date descending; take up to 20.
"""
import json, re, subprocess, sys

REPO = "/home/sandbox/human-essentials"
FROZEN_HEAD = "e5e69704fc49babacb2684bf846560dcb2e63988"
WINDOW_START = "2026-04-24T00:00:00+05:30"

def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args),
                          capture_output=True, text=True, check=True).stdout

log = git("log", "--first-parent", "--format=%H%x1f%cI%x1f%s%x1e", FROZEN_HEAD)
commits = []
for rec in log.split("\x1e"):
    rec = rec.strip()
    if not rec:
        continue
    sha, date, subj = rec.split("\x1f")
    m = re.match(r"^Merge pull request #(\d+)", subj) or re.search(r"\(#(\d+)\)\s*$", subj)
    if not m:
        continue
    commits.append({"sha": sha, "date": date, "subject": subj, "pr": int(m.group(1))})

def changed_files(sha):
    out = git("diff", "--name-only", f"{sha}^1", sha)
    return [l for l in out.splitlines() if l]

for c in commits:
    files = changed_files(c["sha"])
    c["files"] = files
    c["touches_app_lib_ruby"] = any(re.match(r"^(app|lib)/.*\.rb$", f) for f in files)
    c["spec_lines_added"], c["code_files_changed"] = 0, 0

# numstat for spec-add signal on all window commits (cheap enough)
window = [c for c in commits if c["date"] >= WINDOW_START]
for c in window:
    out = git("diff", "--numstat", f"{c['sha']}^1", c["sha"])
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        add, path = parts[0], parts[2]
        if add == "-":
            continue
        if path.startswith("spec/"):
            c["spec_lines_added"] += int(add)
        if re.match(r"^(app|lib)/.*\.rb$", path):
            c["code_files_changed"] += 1

closing = re.compile(r"(?:fixes|closes|resolves)\s+#\d+", re.I)
for c in window:
    body = git("log", "-1", "--format=%B", c["sha"])
    c["signal_fix_title"] = "fix" in c["subject"].lower()
    c["signal_linked_issue"] = bool(closing.search(c["subject"]) or closing.search(body))
    c["signal_test_plus_code"] = c["spec_lines_added"] > 0 and c["code_files_changed"] > 0
    c["bugfix_candidate"] = c["signal_fix_title"] or c["signal_linked_issue"] or c["signal_test_plus_code"]

noise = [c for c in commits if c["touches_app_lib_ruby"]][:15]
bugs = [c for c in window if c["bugfix_candidate"]][:20]

result = {
    "frozen_head": FROZEN_HEAD,
    "window_start": WINDOW_START,
    "counts": {"first_parent_prs_total": len(commits), "window_prs": len(window),
               "noise_selected": len(noise), "bugfix_selected": len(bugs)},
    "noise": [{k: c[k] for k in ("sha", "date", "subject", "pr")} for c in noise],
    "bugfix": [{k: c[k] for k in ("sha", "date", "subject", "pr", "signal_fix_title",
                                  "signal_linked_issue", "signal_test_plus_code")} for c in bugs],
}
json.dump(result, sys.stdout, indent=1)
