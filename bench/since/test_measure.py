# SPDX-License-Identifier: MIT
import unittest
from measure import verdicts, compare


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


if __name__ == '__main__':
    unittest.main()
