#!/usr/bin/env python3
"""Compare the ORIGINAL app Gemfile.lock with the lock after installing the saboteur gem.
The only allowed change is the approved instrumentation addition, nothing else:
  GEM specs:    + '    saboteur (0.12.3)' with sub-lines equal to the BUILT gem's runtime dependencies (passed as args, each already locked)
  DEPENDENCIES: + '  saboteur (= 0.12.3)'
Any other difference (version drift, other gems, CHECKSUMS appearing, platform or ruby changes) fails closed."""
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
            out[k] = out[k][:-1]
    return out

SPEC = "    saboteur (0.12.3)"
DEP = "  saboteur (= 0.12.3)"

def main(a, b, deps):
    A, B = split(open(a).read()), split(open(b).read())
    if list(A) != list(B):
        return "section list changed: %s -> %s" % (list(A), list(B))
    for sec in A:
        if sec in ("GEM", "DEPENDENCIES"):
            continue
        if A[sec] != B[sec]:
            return "section %s changed" % sec
    g = B.get("GEM", [])
    if g.count(SPEC) != 1:
        return "installed lock does not contain exactly one saboteur 0.12.3 spec"
    i = g.index(SPEC)
    sub = []
    j = i + 1
    while j < len(g) and g[j].startswith("      "):
        sub.append(g[j]); j += 1
    want = sorted("      " + d for d in deps)
    if sorted(sub) != want:
        return "saboteur spec dependencies %s are not exactly the built gem's runtime dependencies %s" % (sub, want)
    for d in deps:
        name = d.split(" ")[0]
        if not any(re.match(r"^    " + re.escape(name) + r" \(", l) for l in A.get("GEM", [])):
            return "%s is not locked in the original lock, the addition would need new resolution" % name
    if g[:i] + g[j:] != A["GEM"]:
        return "GEM section differs beyond the saboteur spec"
    d = B.get("DEPENDENCIES", [])
    if d.count(DEP) != 1:
        return "installed lock does not contain exactly one saboteur dependency line"
    if [x for x in d if x != DEP] != A["DEPENDENCIES"]:
        return "DEPENDENCIES differ beyond the saboteur line"
    return None

if __name__ == "__main__":
    r = main(sys.argv[1], sys.argv[2], sys.argv[3:])
    if r:
        print("LOCK_ADD_GATE_FAIL " + r); sys.exit(1)
    print("LOCK_ADD_GATE_OK (only the approved saboteur instrumentation addition)")
