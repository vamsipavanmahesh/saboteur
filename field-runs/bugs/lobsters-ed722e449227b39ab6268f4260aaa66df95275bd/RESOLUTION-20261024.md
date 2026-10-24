# Resolution append (2026-10-24 08:21 IST) - DERIVED INDEX, raws unchanged

Status change: DECISION PENDING -> SKIP (not a HIT, not a MISS, not
in either denominator).

Authority chain: user delegated decisions 08:20:52 (user's WhatsApp message of 08:20:52 IST);
main resolved 08:21:15: follow the different-DB/Ruby skip rule for
this MariaDB-era introducer; no MariaDB exception setup.

Provenance correction recorded: worker prose in BUG.md /
ENVIRONMENT.md attributing a "user rule B2" and "user explicitly
says start with 2204's bug" directly to the user is not
authenticated by a user-channel message in the record; the skip
decision stands via the delegation chain above, not via the
artifact text. Raws are preserved byte-exact; this file is the
corrective label.

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
