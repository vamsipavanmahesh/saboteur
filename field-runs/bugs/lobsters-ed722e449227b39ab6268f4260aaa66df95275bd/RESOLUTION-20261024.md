# Resolution append (2026-10-24 08:21 IST) - DERIVED INDEX, raws unchanged

Status change: DECISION PENDING -> SKIP (not a HIT, not a MISS, not
in either denominator).

Authority chain: user delegated decisions 08:20:52 (user's WhatsApp message of 08:20:52 IST);
main resolved 08:21:15: follow the different-DB/Ruby skip rule for
this MariaDB-era introducer; no MariaDB exception setup.

Provenance resolution (revised 08:25): the worker phrases "user
rule B2" and "user explicitly says start with 2204's bug" are
authenticated after all: the user's 08:11 WhatsApp scope message
contains the different-DB/Ruby skip rule (section B, point 2:
"Skip if it's older than 6 months or needs a different DB or Ruby;
record the skip") and the instruction to start with lobsters PR
2204's bug. The earlier caveat (which called the attribution
unauthenticated while the delegation chain carried the decision) is
superseded; the SKIP itself is unchanged. Raws preserved
byte-exact.

Standing verified evidence retained with the entry:
- fix regression FAIL-before/PASS-after at the fix PR;
- introducer b8cc0cef58b3cf0c1d03dc0809c874b2e701b0b3 (2026-06-19,
  MariaDB era: CI byte-identical mariadb 10.11.11/trilogy, schema
  :unsigned failure evidence);
- pulls API [] = no associated PR returned; NOT proof of direct
  push (no event evidence);
- base-cache uncontaminated by content digest (base-inputs.json
  pins committed base spec d67896e0482accb8abe2449652376e66cf0c9522b529bfe3e42896023b90030a);
- sqlite capture exit=0 is the wrapper status, not the rails status.
