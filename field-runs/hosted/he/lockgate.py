#!/usr/bin/env python3
"""Compare the pre-install patched lock with the installed lock.
Only CHECKSUMS rows of the two added gems (fiddle, saboteur) may be added or gain a sha256 value.
Everything else must be byte-identical, and no version, spec or dependency may drift."""
import re, sys

def split(text):
    out, cur, name = {}, [], "HEAD"
    for line in text.splitlines():
        if re.match(r"^[A-Z][A-Z ]+$", line):
            out[name] = cur; name, cur = line, []
        else:
            cur.append(line)
    out[name] = cur
    for k in out:
        while out[k] and not out[k][-1].strip():
            out[k] = out[k][:-1]   # blank separators belong to no section
    return out

def rows(lines):
    d = {}
    for l in lines:
        m = re.match(r"^ +(\S+) \(([^)]+)\)(?: sha256=([0-9a-f]{64}))?$", l)
        if m:
            d[(m.group(1), m.group(2))] = m.group(3)
        elif l.strip():
            return None
    return d

def main(a, b):
    A, B = split(open(a).read()), split(open(b).read())
    if "CHECKSUMS" in B and "CHECKSUMS" not in A:
        A = dict(A); A["CHECKSUMS"] = []     # a lock with no CHECKSUMS section: treat as empty, additions only
        B_order = [k for k in B]; A_order = [k for k in B_order if k in A]
        if [k for k in B if k != "CHECKSUMS"] != [k for k in A if k != "CHECKSUMS"]:
            return "section list changed: %s -> %s" % (list(A), list(B))
    elif list(A) != list(B):
        return "section list changed: %s -> %s" % (list(A), list(B))
    for sec in A:
        if sec == "CHECKSUMS":
            continue
        if A[sec] != B[sec]:
            return "section %s changed" % sec
    if "CHECKSUMS" not in A:
        return None
    ra, rb = rows(A["CHECKSUMS"]), rows(B["CHECKSUMS"])
    if ra is None or rb is None:
        return "unparseable CHECKSUMS row"
    allowed = {"fiddle", "saboteur"}
    for k in set(ra) | set(rb):
        if ra.get(k, "ABSENT") == rb.get(k, "ABSENT"):
            continue
        if k[0] not in allowed:
            return "checksum row changed for non-added gem %s %s" % k
        if k not in rb:
            return "checksum row removed: %s %s" % k
        if k in ra and ra[k] is not None:
            return "existing checksum value changed: %s %s" % k
    return None

if __name__ == "__main__":
    r = main(sys.argv[1], sys.argv[2])
    if r:
        print("LOCK_GATE_FAIL " + r); sys.exit(1)
    print("LOCK_GATE_OK")
