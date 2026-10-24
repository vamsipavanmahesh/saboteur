#!/usr/bin/env python3
"""selection v3: aware-datetime selection + common ANY-3 bug classifier (crew contract 2026-10-24 09:44).

Noise (clause A): most recent 15 merged PRs (any age) touching app/**/*.rb or lib/**/*.rb,
ordered by aware merge timestamp DESC, PR number DESC tie-break. app/lib-Ruby filter applies
to NOISE ONLY.

Bug candidates (clause B): PRs merged in [2026-04-24T00:00:00+05:30, anchor] eligible under
ANY of: (a) fix-title shared regex; (b) linked-issue (fixes/closes/resolves #N) in PR body;
(c) test+code: touches spec/** AND any non-spec non-doc code file (ANY language; docs/,
*.md/.rdoc/.txt/.lock excluded). NO file-type filter on candidates. Latest 20 by aware
merged_at DESC, number DESC tie-break. Commit resolution: git merge/squash pattern ->
full SHA; UNRESOLVED (not dropped) when git reference missing. Dates normalized via
datetime.fromisoformat (offset-aware); string comparison of mixed-offset dates is banned.
"""
import json, re, subprocess, datetime, sys

REPO = "/home/sandbox/human-essentials"
FROZEN_HEAD = "e5e69704fc49babacb2684bf846560dcb2e63988"
ANCHOR = datetime.datetime.fromisoformat("2026-10-24T08:11:00+05:30")
CUTOFF = datetime.datetime.fromisoformat("2026-04-24T00:00:00+05:30")

fixre = re.compile(r'\bfix(e[ds])?\b|\bbug\b|\bregression\b|\bhotfix\b|\bpatch\b|\bresolve[sd]?\b|\bcrash\b|\berror\b|\bbroken\b', re.I)
linkre = re.compile(r'\b(fix(e[ds])?|close[sd]?|resolve[sd]?)\s+#(\d+)', re.I)

def git(*args):
    return subprocess.run(["git","-C",REPO]+list(args),capture_output=True,text=True).stdout

def parse(s):
    s = s.strip()
    if s.endswith("Z"): s = s[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(s)

# ---- git merged-PR commit index (full SHAs) ----
log = git("log","--first-parent","--format=%H%x1f%cI%x1f%s%x1e",FROZEN_HEAD)
prs = {}
for rec in log.split("\x1e"):
    rec = rec.strip()
    if not rec: continue
    sha, date, subj = rec.split("\x1f")
    m = re.match(r"^Merge pull request #(\d+)", subj) or re.search(r"\(#(\d+)\)\s*$", subj)
    if not m: continue
    prs[int(m.group(1))] = {"sha": sha, "git_date": parse(date), "subject": subj}

# ---- API items (title/body/merged_at authoritative; SHA from git index) ----
items = []
for f in ("/home/sandbox/field-run/api-merged-p1.json","/home/sandbox/field-run/api-merged-p2.json"):
    for it in json.load(open(f))["items"]:
        ma = it.get("pull_request",{}).get("merged_at")
        if not ma: continue
        n = it["number"]
        g = prs.get(n)
        items.append({"pr": n, "title": it.get("title") or "", "body": it.get("body") or "",
                      "merged_at": parse(ma), "sha": g["sha"] if g else None,
                      "git_committer_date": g["git_date"].isoformat() if g else None})
seen=set(); uniq=[]
for it in sorted(items, key=lambda x:(-x["merged_at"].timestamp(), -x["pr"])):
    if it["pr"] in seen: continue
    seen.add(it["pr"]); uniq.append(it)
items = [it for it in uniq if it["merged_at"] <= ANCHOR]
print(f"population: {len(items)} unique merged PRs <= anchor")

def files_of(sha):
    return git("diff","--name-only",f"{sha}^1",sha).splitlines()

# ---- NOISE: latest 15 touching app/lib .rb (aware sort, boundary audit) ----
noise_pool = []
for it in items:
    if not it["sha"]: continue
    fl = files_of(it["sha"]); it["files_n"] = len(fl)
    if any(re.match(r"^(app|lib)/.*\.rb$", f) for f in fl):
        noise_pool.append(it)
noise = noise_pool[:15]
b15, b16 = noise_pool[14], noise_pool[15] if len(noise_pool)>15 else None
print(f"noise boundary: #15={b15['pr']} @{b15['merged_at'].isoformat()} vs #16={b16['pr'] if b16 else None} @{b16['merged_at'].isoformat() if b16 else 'n/a'}")

# ---- BUG: ANY-3 over window ----
window = [it for it in items if it["merged_at"] >= CUTOFF]
res=[]
for it in window:
    sig=[]
    if fixre.search(it["title"]): sig.append("fix-title")
    m = linkre.search(it["body"])
    if m and not re.search(r'#0*1\b\s*<?!-*\s*fill issue number|Resolves #001 \s*<!--', it["body"]):
        sig.append("linked-issue")
    elif m:
        it["invalidated_signals"]=[{"signal":"linked-issue","reason":"template placeholder 'Resolves #001 <!--fill issue number-->' - no real issue; content-proof FAILED"}]
    it["signals"]=sig
need=[it for it in window if not it["signals"]]
print(f"phase A: {len(window)-len(need)} eligible via title/linked of {len(window)} in window")
hits=miss=nocommit=0
for it in need:
    if not it["sha"]:
        it["eligibility"]="unresolved"; nocommit+=1; continue
    fl = files_of(it["sha"])
    has_spec = any(f.startswith("spec/") for f in fl)
    code = [f for f in fl if not f.startswith(("spec/","docs/")) and not f.lower().endswith((".md",".rdoc",".txt",".lock"))]
    it["source_types"]=sorted({f.split("/")[0] for f in fl})
    if has_spec and code:
        it["signals"].append("test-added-code"); it["eligibility"]="eligible"; hits+=1
    else:
        it["eligibility"]="ineligible"; miss+=1
print(f"phase B: +{hits} test-added-code; {miss} ineligible; {nocommit} unresolved")
for it in window:
    it.setdefault("eligibility", "eligible" if it["signals"] else "unresolved")
elig = sorted([it for it in window if it["eligibility"]=="eligible"],
              key=lambda x:(-x["merged_at"].timestamp(), -x["pr"]))
bugs = elig[:20]
print(f"eligible={len(elig)}; bug-20 = {[it['pr'] for it in bugs]}")
print(f"noise-15 = {[it['pr'] for it in noise]}")

out = {"version":3, "anchor":ANCHOR.isoformat(), "cutoff":CUTOFF.isoformat(),
 "contract":"common ANY-3 (fix-title shared regex | linked-issue body | test+any-nonspec-nondoc-code); noise app/lib-rb filter; aware-datetime ordering; frozen before results",
 "noise":[{"pr":it["pr"],"sha":it["sha"],"merged_at":it["merged_at"].isoformat(),"title":it["title"]} for it in noise],
 "noise_boundary_audit":{"p15":{"pr":b15["pr"],"merged_at":b15["merged_at"].isoformat()},
   "p16":{"pr":b16["pr"],"merged_at":b16["merged_at"].isoformat()} if b16 else None},
 "bug_candidates":[{"pr":it["pr"],"sha":it["sha"],"merged_at":it["merged_at"].isoformat(),
   "title":it["title"],"signals":it["signals"],"source_types":it.get("source_types")} for it in bugs],
 "window_counts":{"in_window":len(window),"eligible":len(elig),
   "unresolved":[{"pr":it["pr"],"reason":"no git commit reference"} for it in window if it["eligibility"]=="unresolved"]}}
json.dump(out, open("/home/sandbox/field-run/selection-v3.json","w"), indent=1)
print("wrote selection-v3.json")
