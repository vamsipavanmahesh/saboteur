#!/usr/bin/env python3
"""Neutral fake-kill check, the same for both tools.

A kill is fake when the test that killed the mutant also fails with the code
unchanged: the failure came from the test environment (leaked data, load
order, a broken setup), not from the mutant.

    fake_kill_check.py sample TOOL REPORT N SEED > killers.txt
        TOOL saboteur: REPORT is its Stryker JSON; a kill's killers are
        its killedBy test ids. TOOL mutineer: REPORT is a --matrix JSON
        report; a kill's killers are its killed_by tests.
        Prints one line per sampled kill: mutant id, then its killing
        example ids, tab-separated.

    fake_kill_check.py judge KILLERS RESULTS_JSON > verdicts.json
        RESULTS_JSON is RSpec's JSON output from running every killing
        example on the unchanged code. A kill is fake when any of its
        killers failed there.
"""
import json
import random
import sys


def saboteur_kills(report):
    tests = {}
    for test_file in report.get("testFiles", {}).values():
        for test in test_file.get("tests", []):
            tests[test["id"]] = test["name"]
    for source in report["files"].values():
        for mutant in source["mutants"]:
            if mutant["status"] == "Killed" and mutant.get("killedBy"):
                yield mutant["id"], [tests.get(t, t) for t in mutant["killedBy"]]


def mutineer_kills(report):
    tests = report["matrix"]["tests"]
    for mutant in report["matrix"]["mutants"]:
        if mutant["status"] == "killed" and mutant.get("killed_by"):
            yield mutant["id"], [tests[i]["id"] for i in mutant["killed_by"]]


def sample(tool, path, count, seed):
    report = json.load(open(path))
    kills = list(saboteur_kills(report) if tool == "saboteur" else mutineer_kills(report))
    random.Random(seed).shuffle(kills)
    for mutant_id, killers in kills[:count]:
        print("\t".join([mutant_id] + killers))


def judge(killers_path, results_path):
    failed = {e["id"] for e in json.load(open(results_path))["examples"] if e["status"] == "failed"}
    verdicts = []
    for line in open(killers_path):
        mutant_id, *killers = line.rstrip("\n").split("\t")
        bad = [k for k in killers if k in failed]
        verdicts.append({"mutant": mutant_id, "killers": killers, "fake": bool(bad), "failing_unchanged": bad})
    json.dump({"checked": len(verdicts), "fake": sum(v["fake"] for v in verdicts), "kills": verdicts},
              sys.stdout, indent=1)


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "sample":
        sample(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
    elif command == "judge":
        judge(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
