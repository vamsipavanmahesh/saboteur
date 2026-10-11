#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Measure full and diff mode on the same checkout, in alternating pairs."""
import argparse
import collections
import json
import pathlib
import platform
import subprocess
import time


def verdicts(report):
    return {(path, mutant['id']): mutant['status']
            for path, entry in report['files'].items() for mutant in entry['mutants']}


def compare(full, diff):
    for identity, status in diff.items():
        if full.get(identity) != status:
            raise ValueError(f'verdict mismatch: {identity}: {full.get(identity)} != {status}')
    return len(diff)


def run(mode, pair, base, output):
    name = f'pair-{pair}-{mode}'
    report_path = output / f'{name}.json'
    command = ['bundle', 'exec', 'ruby', 'exe/saboteur', 'run', '--config',
               'bench/since/workload.yml', '--json', str(report_path)]
    if mode == 'diff':
        command += ['--since', base]
    report_path.unlink(missing_ok=True)
    started = time.monotonic()
    with (output / f'{name}.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=log, check=False)
    elapsed = time.monotonic() - started
    if result.returncode not in (0, 1):
        raise ValueError(f'{name}: tool/config error, exit {result.returncode}')
    if not report_path.is_file():
        raise ValueError(f'{name}: fresh report was not written')
    report = json.loads(report_path.read_text())
    statuses = verdicts(report)
    invalid = set(statuses.values()) - {'Killed', 'Survived', 'NoCoverage', 'Ignored'}
    if invalid:
        raise ValueError(f'{name}: invalid benchmark verdict: {sorted(invalid)}')
    return {'mode': mode, 'pair': pair, 'command': command, 'exit': result.returncode,
            'wall_seconds': elapsed, 'mutants': len(statuses),
            'statuses': dict(collections.Counter(statuses.values()))}, statuses


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--first-pair', type=int, default=1)
    parser.add_argument('--pairs', type=int, default=5)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True, exist_ok=True)
    evidence = []
    for pair in range(arguments.first_pair, arguments.first_pair + arguments.pairs):
        modes = ['full', 'diff'] if pair % 2 else ['diff', 'full']
        results = {}
        for mode in modes:
            record, statuses = run(mode, pair, arguments.base, arguments.output)
            evidence.append(record)
            results[mode] = statuses
            print(json.dumps(record), flush=True)
        compare(results['full'], results['diff'])
        (arguments.output / f'pair-{pair}-measurements.json').write_text(
            json.dumps(evidence[-2:], indent=2) + '\n')
    metadata = {'platform': platform.platform(),
                'ruby': subprocess.check_output(['ruby', '-v'], text=True).strip(),
                'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                'base': subprocess.check_output(['git', 'rev-parse', arguments.base], text=True).strip(),
                'merge_base': subprocess.check_output(['git', 'merge-base', arguments.base, 'HEAD'],
                                                      text=True).strip()}
    (arguments.output / 'environment.json').write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()
