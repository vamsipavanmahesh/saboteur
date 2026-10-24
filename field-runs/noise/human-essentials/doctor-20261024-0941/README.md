# HE doctor attempt 1 - tool-version contamination incident + correction (2026-10-24 09:41 IST)

PUBLIC CORRECTION. The first human-essentials doctor run (2026-10-24 08:55:14 -> 09:35:36 IST, wall 311.04s, exit 3, "baseline run 1 stopped: exceeded deadline" at the 300s deadline) executed with the REGISTRY saboteur 0.12.3, NOT the pinned build. Cause: the vendored-artifact copy into the era tree's vendor/cache failed (missing mkdir) and the failure was unchecked; `bundle install` then fetched saboteur from rubygems.org without --local (bundle-install.log: "Fetching saboteur 0.12.3 ... from https://rubygems.org"). Registry 0.12.3 is NOT the pinned source (18 lib files differ from pin 6f87ccc98377bf0c23f3cf409006f0464c2aa67c).

## Standing corrections to earlier statements
- The 300s-deadline doctor result is an ENVIRONMENT-timing sample with the WRONG TOOL VERSION. It is not a pin metric, not a baseline, and not evidence about HE suite behavior under the pinned tool. It is retained as a raw (measurement.doctor.json, doctor-suite.log) with this caveat; its 311.04s wall must not feed timeout sizing or any map/baseline claim.
- Scope wording correction: the doctor WAS a baseline attempt. The correct statement is "0 completed HE baselines / 0 measured rows", never "no baseline activity exists".
- No HE maps, replays, survivors, or counts exist. The 300s deadline is provisional; the real baseline timeout is set from the FIXED doctor's measured actual and then validated.

## Fix (09:40 IST, PIN-PROOF.txt + bundle-install2.log)
Vendored artifact (sha256 57ac8099a6f78ff713d6f361ef7e14632ca1676acdec02d15adcab46f0ca0dd4, content byte-identical to the pin per the 09:22 audit) placed in the era tree's vendor/cache (mkdir-fatal copy), `bundle install --local` (no registry), claimed payload diff vs the pinned build = 0 differing paths over lib/ (pin-payload-diff.txt, empty). Tree: he-5723-era @ ace6151d2296a3b252d5ccdbcc4a838caf2d388c. config/saboteur.rb: include app/** + lib/** per user scope, rails mode, jobs=1.

## Audit notes (open receipt gaps, none block the correction itself)
1. Both installs landed in the SAME GEM_HOME (/home/sandbox/bundle) and both logs report "275 gems now installed": with the same version already present, bundler can skip reinstalling saboteur, which would leave REGISTRY bytes in place. The empty payload diff is the only guard against exactly that, but the diff's COMMAND and BOTH ROOTS are not recorded in the packet. Required before the fixed doctor run: the exact diff command + the two directory roots, or the installed-vs-artifact .sha256 lists in the shape the other runs publish.
2. Ruby patchlevel is not recorded in this packet (runtime-digest input); include `ruby -v` in the fixed doctor's receipt.
3. Suite observation (raw, no claim): doctor-suite.log shows spec/support/deadline_day_fields_shared_example.rb:77 loaded twice ("The new definition will overwrite the original one") - an HE-suite double-load quirk to keep in view for test-ID stability.
4. The Landlock ABI 2 vs 3 sandbox-degrade warning appears in this run too; disclosed, consistent with the other runs.
