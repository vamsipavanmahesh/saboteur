#!/usr/bin/env python3
"""Real-bug detection: with the tests from before a fix, did a tool report a
survivor on or next to a line the fix changed?

    bug_detect.py FIXED_LINES_JSON SABOTEUR_JSON MUTINEER_JSON [SLACK]

FIXED_LINES_JSON maps each source file to [first, last] line ranges in the
pre-fix file. SLACK (default 2) is how many lines away still counts as
"next to".
"""
import json
import sys


def near(line, ranges, slack):
    return any(first - slack <= line <= last + slack for first, last in ranges)


def saboteur_survivors(report):
    for path, source in report["files"].items():
        for mutant in source["mutants"]:
            if mutant["status"] == "Survived":
                yield path, mutant["location"]["start"]["line"], mutant["mutatorName"]


def mutineer_survivors(report):
    for survivor in report["survivors"]:
        yield survivor["file"], survivor["line"], survivor["operator"]


def detect(fixed, survivors, slack):
    hits = []
    for path, line, operator in survivors:
        ranges = next((r for f, r in fixed.items() if path.endswith(f) or f.endswith(path)), None)
        if ranges and near(line, ranges, slack):
            hits.append({"file": path, "line": line, "operator": operator})
    return hits


if __name__ == "__main__":
    fixed = json.load(open(sys.argv[1]))
    slack = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    result = {}
    for tool, path, survivors in (("saboteur", sys.argv[2], saboteur_survivors),
                                  ("mutineer", sys.argv[3], mutineer_survivors)):
        hits = detect(fixed, survivors(json.load(open(path))), slack)
        result[tool] = {"detected": bool(hits), "survivors_near_fix": hits}
    json.dump(result, sys.stdout, indent=1)
