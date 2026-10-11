# Rejected kills

The terminal and JSON report count mutation kills rejected by the existing
unchanged-method check. JSON adds `rejectedKills` (an integer, including zero).
These mutants remain errors, not kills, and stay outside the score. The count
is per mutant, not per distinct test sequence. Named and unnamed kills count;
timeout checks, other errors and reused verdicts do not. Worker transport keeps
the rejection flag, so serial and parallel runs use the same accounting.

This does not introduce another check or rerun rejected errors from the cache.
Errors are not cached. A reused kill is not fresh evidence and does not count as
a rejected kill in this run.
