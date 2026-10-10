#!/usr/bin/env python3
"""For mutants both tools made identically, apply each edit by hand, run the
whole suite once, restore the file, and record whether any test failed.

    overlap_check.py OVERLAP_JSON TARGET_DIR -- SUITE_COMMAND...

SUITE_COMMAND must write RSpec JSON to $OUT (set per mutant).
"""
import json
import os
import subprocess
import sys


def apply(text, start, end, replacement):
    lines = text.split("\n")
    offset = lambda pos: sum(len(l) + 1 for l in lines[: pos["line"] - 1]) + pos["column"] - 1
    return text[: offset(start)] + replacement + text[offset(end):]


def main():
    overlap = json.load(open(sys.argv[1]))
    target = sys.argv[2]
    command = sys.argv[sys.argv.index("--") + 1:]
    results = []
    for n, item in enumerate(overlap):
        path = os.path.join(target, item["file"])
        original = open(path).read()
        out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), f"overlap-{n}.rspec.json")
        try:
            open(path, "w").write(apply(original, item["start"], item["end"], item["replacement"]))
            subprocess.run(command, cwd=target, env={**os.environ, "OUT": out},
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            open(path, "w").write(original)
        summary = json.load(open(out))["summary"]
        if summary["example_count"] == 0:
            sys.exit(f"no examples ran for {item['file']}:{item['start']['line']}; the suite command is broken")
        failed = [e["id"] for e in json.load(open(out))["examples"] if e["status"] == "failed"]
        results.append({**item, "examples": summary["example_count"], "failures": summary["failure_count"],
                        "failed_ids": failed[:5]})
        print(item["file"], item["start"]["line"], "failures:", summary["failure_count"], flush=True)
    json.dump(results, open(sys.argv[1].replace(".json", "-results.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
