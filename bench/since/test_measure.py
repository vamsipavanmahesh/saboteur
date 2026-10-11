# SPDX-License-Identifier: MIT
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from measure import verdicts, compare, run


class VerdictComparisonTest(unittest.TestCase):
    def test_checks_every_diff_mutant_not_just_totals(self):
        full = {('file.rb', 'a'): 'Killed', ('file.rb', 'b'): 'Survived'}
        diff = {('file.rb', 'a'): 'Survived'}
        with self.assertRaises(ValueError):
            compare(full, diff)

    def test_rejects_missing_mutants(self):
        with self.assertRaises(ValueError):
            compare({}, {('file.rb', 'a'): 'Killed'})

    def test_accepts_a_matching_subset(self):
        self.assertEqual(compare({('f', 'a'): 'Killed', ('f', 'b'): 'Survived'},
                                 {('f', 'a'): 'Killed'}), 1)

    def test_uses_file_and_digest_as_identity(self):
        report = {'files': {'f': {'mutants': [{'id': 'a', 'status': 'Killed'}]}}}
        self.assertEqual(verdicts(report), {('f', 'a'): 'Killed'})


class MeasurementOutputTest(unittest.TestCase):
    def measure(self, output, statuses=None):
        def execute(*args, **kwargs):
            report_path = output / 'pair-1-full.json'
            self.assertFalse(report_path.exists(), 'old report must be removed before execution')
            if statuses is not None:
                report = {'files': {'f': {'mutants': [
                    {'id': str(index), 'status': status}
                    for index, status in enumerate(statuses)]}}}
                report_path.write_text(json.dumps(report))
            return SimpleNamespace(returncode=1)
        with patch('measure.subprocess.run', side_effect=execute):
            return run('full', 1, 'main', output)

    def test_rejects_missing_report(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'report was not written'):
                self.measure(pathlib.Path(directory))

    def test_removes_stale_report_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory)
            (output / 'pair-1-full.json').write_text('{"files": {}}')
            with self.assertRaisesRegex(ValueError, 'report was not written'):
                self.measure(output)

    def test_accepts_fresh_report(self):
        with tempfile.TemporaryDirectory() as directory:
            record, _ = self.measure(pathlib.Path(directory), ['Killed', 'Survived'])
            self.assertEqual(record['mutants'], 2)

    def test_rejects_partial_error_and_timeout_reports(self):
        for status in ['RuntimeError', 'Timeout', 'Error']:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, 'invalid benchmark verdict'):
                    self.measure(pathlib.Path(directory), ['Killed', status])


if __name__ == '__main__':
    unittest.main()
