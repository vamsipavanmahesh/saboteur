#!/usr/bin/env python3
"""safe_unzip.py <zip> <dest>: extract an untrusted artifact zip. Regular files only, safe names, bounded count/size, no overwrite."""
import os, re, stat, sys, zipfile
NAME = re.compile(r"\A[A-Za-z0-9._@=+,-]+\Z")
z, dest = sys.argv[1:3]
MAXN, MAXF, MAXT = 5000, 500 * 1024 * 1024, 2 * 1024 ** 3
def die(m): print("EXTRACT_BLOCK: " + m); sys.exit(1)
with zipfile.ZipFile(z) as zf:
    infos = zf.infolist()
    if len(infos) > MAXN: die("too many members")
    total = 0; seen = set()
    for i in infos:
        n = i.filename
        if n.startswith("/") or "\\" in n or ".." in n.split("/"): die("unsafe path " + n)
        parts = n.rstrip("/").split("/") if i.is_dir() else n.split("/")
        if "" in parts or "." in parts or (n.endswith("/") and not i.is_dir()): die("non-canonical member name " + n)
        if not parts or not all(NAME.match(p) and not p.startswith(".") for p in parts): die("unsafe name " + n)
        mode = i.external_attr >> 16
        if stat.S_IFMT(mode) and stat.S_IFMT(mode) not in (stat.S_IFREG, stat.S_IFDIR): die("non-regular member " + n)
        if n in seen: die("duplicate member " + n)
        seen.add(n)
        if i.file_size > MAXF: die("member too large " + n)
        total += i.file_size
    if total > MAXT: die("archive too large")
    if os.path.islink(dest): die("destination is a symlink")
    if os.path.exists(dest) and (not os.path.isdir(dest) or os.listdir(dest)): die("destination is not an empty directory")
    os.makedirs(dest, exist_ok=True)
    root = os.path.realpath(dest)
    for i in infos:
        t = os.path.join(dest, i.filename)
        if os.path.commonpath([root, os.path.realpath(t)]) != root: die("member resolves outside the destination " + i.filename)
        if i.is_dir(): os.makedirs(t, exist_ok=True); continue
        os.makedirs(os.path.dirname(t), exist_ok=True)
        with zf.open(i) as src, open(t, "xb") as out:
            n = 0
            while True:
                b = src.read(1 << 20)
                if not b: break
                n += len(b)
                if n > MAXF: die("member exceeded declared size " + i.filename)
                out.write(b)
print("EXTRACT_OK %d members" % len(infos))
