# 2204 M-side receipts (attempt c1, 2026-10-24)
- Map line (run's own): "747 subjects, 861 tests in coverage map"
- Key c091018a963bc80c9d388f788d94d79879624351d483c728f7481d0a86905b2c; inputs: seed 1, settings 240ea092895a078446a2d06a4e9aa4076071e7d4f772f56470ed7393860aa5a0, runtime 712bc81aed3f7412b0bfc912f49204064b8c0a9de8a652e693c3da15d1b51e33, root 5681455113f8824edd2a4dbe17a074c4cd5c2c8aad8a70fbcd38f25889be0535, format 2
- coverage JSON: 861 tests (jq .tests|length)
- Driver: MEASURED exit=130 wall=986.61s rss_kb=493900 (envelope in pr2204-headmap-driver-c1.log)
- exit=130 = observer BOUNDARY_STOP_ARTIFACTS_FRESH_VERIFIED 09:43:00 (pr2204-obs-c1.log): identity re-verified (PID 24068 + PGID 24059 + cmdline + /proc starttime ticks 783519) before AND after the 5s settle, then SIGINT to PGID 24059 only
- Pointer freshness: whole-suite-map-v2 mtime 09:42 >= T0 1792814201; pre-existing 07:43 pointer ignored by the freshness check
- Map log tail: last progress line "182 s elapsed, 700/861 examples (81%)" then the map line; no shutdown crash lines
- Ownership at launch: driver setsid PGID 24059 (headmap2.sh 24059 -> runmeasured.py 24067 -> supervisor 24068); saboteur-internal suite child 24106 own PGID (saboteur-managed); observer setsid PGID 24099 (outside measured group)
- Runner hashes: headmap2.sh 255d0ae9e5523370e8bc85d85b25af3a7ab3424bc04de8b02089ffa246f8888b, pairobs.sh 6690b470efd02abfcae456839c13ce28e9fd5a9bd5ffb9817e9a08cfed99d835
