#!/usr/bin/env python3
"""One row per run: counts in the shared status names (PHASE1.md section 5),
plus wall time, peak memory and leftovers from the watchdog.

    summarize.py RUNS_DIR > summary.json

saboteur rows also carry "matched": the same counts with its unmatched
operators (body_true, body_raise, or_assign) filtered out.
"""
import glob
import json
import os
import re
import sys

SABOTEUR_UNMATCHED = {"body_true", "body_raise", "or_assign"}


def saboteur_status(mutant):
    status = mutant["status"]
    reason = mutant.get("statusReason") or ""
    if status == "Killed":
        return "killed"
    if status == "Survived":
        return "survived"
    if status == "Timeout":
        return "timeout"
    if status == "NoCoverage":
        return "no_coverage"
    if status == "RuntimeError":
        return "resource_limit" if reason.startswith("resource limit:") else "error"
    if status == "Ignored":
        return "subsumed" if reason == "coarse mutant survived" else "other"
    return "other"


def saboteur_counts(report, keep=lambda operator: True):
    counts = {}
    for source in report["files"].values():
        for mutant in source["mutants"]:
            if keep(mutant["mutatorName"]):
                status = saboteur_status(mutant)
                counts[status] = counts.get(status, 0) + 1
    counts["total"] = sum(counts.values())
    return counts


def mutineer_counts(report):
    s = report["summary"]
    counts = {"killed": s["killed"], "survived": s["survived"], "timeout": s["timeout"],
              "error": s["errored"], "no_coverage": s["no_coverage"], "ran_at_load": s["ran_at_load"],
              "other": s["uncapturable"] + s["unplaceable"] + s["ignored"],
              "invalid": s["skipped_invalid"]}
    counts["total"] = s["total"]
    return counts


def watchdog(path):
    try:
        line = open(path).read().strip().splitlines()[-1]
    except (OSError, IndexError):
        return {}
    fields = dict(re.findall(r"(\w+)=([\w.]+)", line))
    return {"exit": int(fields.get("exit", -1)), "wall_s": float(fields.get("wall", "0").rstrip("s")),
            "peak_rss_mb": int(fields.get("peak_rss", "0MB").rstrip("MB")),
            "peak_procs": int(fields.get("peak_procs", 0)), "leftovers": int(fields.get("leftovers", 0))}


def rows(runs_dir):
    for path in sorted(glob.glob(os.path.join(runs_dir, "*.json"))):
        name = os.path.basename(path)[:-5]
        report = json.load(open(path))
        tool = "saboteur" if "files" in report else "mutineer"
        row = {"run": name, "tool": tool, **watchdog(os.path.join(runs_dir, name + ".watchdog"))}
        if tool == "saboteur":
            row["counts"] = saboteur_counts(report)
            row["matched"] = saboteur_counts(report, lambda operator: operator not in SABOTEUR_UNMATCHED)
        else:
            row["counts"] = mutineer_counts(report)
        executed = sum(row["counts"].get(k, 0) for k in ("killed", "survived", "timeout", "error", "resource_limit"))
        row["executed"] = executed
        row["s_per_executed_mutant"] = round(row["wall_s"] / executed, 3) if executed and "wall_s" in row else None
        decided = row["counts"].get("killed", 0) + row["counts"].get("survived", 0)
        row["score_pct"] = round(100.0 * row["counts"].get("killed", 0) / decided, 1) if decided else None
        yield row


if __name__ == "__main__":
    json.dump(list(rows(sys.argv[1])), sys.stdout, indent=1)
