#!/usr/bin/env bash
# replay.sh <pr>: scoped PR replay at the PR's ledger HEAD, same canonical root, with the era snapshot triple restored unchanged.
# Needs MAP_ART_DIR: the downloaded, unmodified output directory of a completed map job for this PR's era.
source "$(dirname "$0")/lib.sh"
PR=${1:?pr}; : "${MAP_ART_DIR:?}"
read -r _ H ERA S < <(row "$PR") || true; [[ "${H:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "REPLAY_BLOCK: unknown PR $PR"; exit 1; }
L="$OUT/replay.log"
# 0. the producer artifact: sealed manifest, expected era and snapshot
( cd "$MAP_ART_DIR" && sha256sum -c --quiet MANIFEST.sha256 ) || { echo "REPLAY_BLOCK: producer artifact manifest does not verify" | tee -a "$L"; exit 1; }
[ "$(cat "$MAP_ART_DIR/map-era.txt")" = "$ERA" ] && [ "$(cat "$MAP_ART_DIR/map-head-sha.txt")" = "$S" ] || { echo "REPLAY_BLOCK: artifact is not the $ERA map at $S" | tee -a "$L"; exit 1; }
( cd "$MAP_ART_DIR/triple" && sha256sum -c --quiet "$MAP_ART_DIR/TRIPLE.sha256" ) || { echo "REPLAY_BLOCK: triple bytes differ from the producer receipt" | tee -a "$L"; exit 1; }
[ "$(jq -r '.boundary.state' "$MAP_ART_DIR/map-meta.json")" = sent ] || { echo "REPLAY_BLOCK: producer has no validated boundary" | tee -a "$L"; exit 1; }
bash "$RECIPE_DIR/prep.sh" "$H" || { echo "REPLAY_BLOCK: prep failed" | tee -a "$L"; exit 1; }
cd "$APP_ROOT"
B=$(git rev-parse "$H^1"); git cat-file -e "$B^{commit}" && git merge-base --is-ancestor "$B" "$H" || { echo "REPLAY_BLOCK: base is not H^1 ancestor" | tee -a "$L"; exit 1; }
[ "$(git rev-parse HEAD)" = "$H" ] || { echo "REPLAY_BLOCK: HEAD != ledger head" | tee -a "$L"; exit 1; }
echo "REPLAY_IDENTITY pr=$PR head=$H base=$B era=$ERA snapshot=$S head_to_snapshot_commits=$(git rev-list --count "$H..$S" 2>/dev/null || echo unknown) head_is_ancestor_of_snapshot=$(git merge-base --is-ancestor "$H" "$S" && echo yes || echo no)" | tee -a "$L"
{ echo "SNAPSHOT_VS_HEAD_INVENTORY (git diff --stat, disclosure only; accepted app-config drift tolerance, not a zero-drift check)"
  git diff --stat "$S" "$H" -- Gemfile Gemfile.lock config || true; } > "$OUT/snapshot-drift.txt"
require_doctor | tee -a "$L"; [ "${PIPESTATUS[0]}" = 0 ] || { echo "REPLAY_BLOCK: no green doctor for this recipe and identity" | tee -a "$L"; exit 1; }
# snapshot compatibility, native prefix inputs included (presence AND hash), before the pointer may be used
cd "$APP_ROOT"; MA="$MAP_ART_DIR"; bad=""
[ "$(sha256sum "$OUT/deps/1-Gemfile.lock.original" | cut -d' ' -f1)" = "$(sha256sum "$MA/deps/1-Gemfile.lock.original" | cut -d' ' -f1)" ] || bad="$bad original-lock"
[ "$(sha256sum "$OUT/deps/3-Gemfile.lock.installed" | cut -d' ' -f1)" = "$(sha256sum "$MA/deps/3-Gemfile.lock.installed" | cut -d' ' -f1)" ] || bad="$bad installed-lock"
[ "$(grep -m1 "^SABOTEUR_BIN" "$OUT/RECEIPTS.txt")" = "$(grep -m1 "^SABOTEUR_BIN" "$MA/RECEIPTS.txt")" ] || bad="$bad tool-version"
[ "$(sha256sum "$OUT/deps/config.saboteur.rb" | cut -d' ' -f1)" = "$(sha256sum "$MA/deps/config.saboteur.rb" | cut -d' ' -f1)" ] || bad="$bad config"
for f in config/saboteur_custom_map.rb config/saboteur_ignore.rb; do
  mine=$(grep -E "^(PRESENT|ABSENT) $f( |$)" "$OUT/RECEIPTS.txt" || true); theirs=$(grep -E "^(PRESENT|ABSENT) $f( |$)" "$MA/RECEIPTS.txt" || true)
  [ -n "$mine" ] && [ "$mine" = "$theirs" ] || bad="$bad $f"
done
# Gemfile: byte-equal, or only comment lines differ (the disclosed 5656 typo class); anything else blocks
# Gemfile: byte-equal, or the ONE frozen exact pair (PR 5656 head vs the S2 snapshot Gemfile) whose only difference is the comment typo JAVSCRIPT -> JAVASCRIPT
if ! cmp -s "$OUT/deps/1-Gemfile.original" "$MA/deps/1-Gemfile.original"; then
  H5656=63ddd3a8ff414134f9174aa9dce873b4202fec7888389f0a35a7960c505b0cb5; S2G=b5afae36a49a6aebc4ebbccf67db7ac5d07a3289f800b26f6f55b4c83d328205
  mineg=$(sha256sum "$OUT/deps/1-Gemfile.original" | cut -d' ' -f1); theirg=$(sha256sum "$MA/deps/1-Gemfile.original" | cut -d' ' -f1)
  if [ "$PR" = 5656 ] && [ "$mineg" = "$H5656" ] && [ "$theirg" = "$S2G" ] && cmp -s <(sed 's/JAVSCRIPT/JAVASCRIPT/' "$OUT/deps/1-Gemfile.original") <(sed 's/JAVSCRIPT/JAVASCRIPT/' "$MA/deps/1-Gemfile.original"); then
    echo "GEMFILE_FROZEN_PAIR_ACCEPTED pr=5656 head_gemfile=$mineg s2_gemfile=$theirg typo-only" | tee -a "$L"
  else bad="$bad Gemfile-differs-outside-the-frozen-5656-S2-pair"; fi
fi
[ -z "$bad" ] || { echo "REPLAY_BLOCK: snapshot is not compatible with this PR head:$bad" | tee -a "$L"; exit 1; }
echo "SNAPSHOT_COMPAT_OK original lock, installed lock, config, custom map and ignore presence+hash identical" | tee -a "$L"
bash "$RECIPE_DIR/dbassets.sh" || { echo "REPLAY_BLOCK: db/assets failed" | tee -a "$L"; exit 1; }
# 1. restore exactly the triple, nothing else, and re-validate identity against THIS job's native identity values
rm -rf .saboteur; mkdir -p .saboteur
KEY=$(tr -d '[:space:]' < "$MAP_ART_DIR/triple/whole-suite-map-v2")
[[ "$KEY" =~ ^[0-9a-f]{64}$ ]] || { echo "REPLAY_BLOCK: pointer is not a 64-hex key" | tee -a "$L"; exit 1; }
MM="$MAP_ART_DIR/map-meta.json"
jq -e --arg k "$KEY" --arg root "$APP_ROOT" '.exit_code==130 and (.stopped_by==null) and .boundary.state=="sent" and .boundary.pointer_key==$k and .cwd==$root and (.command|test("saboteur run --all --baseline-passes 1 --max-duration 35m --jobs 1 --verbose"))' "$MM" >/dev/null || { echo "REPLAY_BLOCK: producer meta does not match the approved map command/boundary" | tee -a "$L"; exit 1; }
for f in "coverage-$KEY.json" "inputs-$KEY.json" whole-suite-map-v2; do [ "$(sha256sum "$MAP_ART_DIR/triple/$f" | cut -d' ' -f1)" = "$(jq -r --arg f "$f" '.boundary.sha256[$f]' "$MM")" ] || { echo "REPLAY_BLOCK: $f differs from the producer-validated boundary hash" | tee -a "$L"; exit 1; }; done
for f in "coverage-$KEY.json" "inputs-$KEY.json" whole-suite-map-v2; do cp -p "$MAP_ART_DIR/triple/$f" ".saboteur/$f"; done
[ "$(ls -A .saboteur | wc -l)" = 3 ] || { echo "REPLAY_BLOCK: .saboteur must hold exactly the triple" | tee -a "$L"; exit 1; }
RECIPE_DIR="$RECIPE_DIR" OUT="$OUT" KEY="$KEY" APP_ROOT="$APP_ROOT" python3 - <<'PY' | tee -a "$L"
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("m", os.environ["RECIPE_DIR"] + "/measure3.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ident = json.load(open(os.environ["OUT"] + "/deps/expected-identity.json")); k = os.environ["KEY"]; d = ".saboteur/"
bad = m.validate_pair(d + f"coverage-{k}.json", d + f"inputs-{k}.json", d + "whole-suite-map-v2", k, os.environ["APP_ROOT"], 1, ident["runtime"], ident["settings"])
if bad:
    print("REPLAY_BLOCK: restored triple does not match this job's native identity: " + bad); sys.exit(1)
print("TRIPLE_RESTORED_AND_IDENTITY_OK key=" + k)
PY
capped 300 bundle exec ruby -rjson -e '
require "saboteur"
k = ARGV[0]; cov = File.read(".saboteur/coverage-#{k}.json")
Saboteur::Selection::CoverageMap.from_json(cov)
snap = Saboteur::Engine::CoverageInputsSnapshot.latest(".saboteur", Dir.pwd)
abort("native snapshot loader rejected the restored pair") unless snap && snap["map_key"] == k
puts "NATIVE_LOADER_ACCEPTS_PAIR key=#{k}"' "$KEY" | tee -a "$L"
[ "${PIPESTATUS[0]}" = 0 ] || { echo "REPLAY_BLOCK: native loader rejected the restored triple" | tee -a "$L"; exit 1; }
cp "$MM" "$OUT/producer-map-meta.json"; cp "$MAP_ART_DIR/job-start.txt" "$OUT/producer-job-start.txt"; cp "$MAP_ART_DIR/recipe-pin.txt" "$OUT/producer-recipe-pin.txt"
sha256sum .saboteur/* | tee "$OUT/pointer-receipt-before.txt" | tee -a "$L"
# 2. replay: flags as documented for the pr preset; budget never shrunk
NEED=2700   # historical replay outer bound (the native pr preset also carries its own 10m max-duration)
[ "$(left_s)" -ge $(( NEED + 900 )) ] || { echo "REPLAY_BLOCK: job time left ($(left_s)s) cannot cover the ${NEED}s outer bound; not shrinking it" | tee -a "$L"; exit 1; }
stamp "REPLAY_START cmd='saboteur pr --since $B --jobs 1 --json --html' outer=${NEED}s" | tee -a "$L"
rc=0; measured "$OUT/replay-meta.json" "$NEED" bundle exec saboteur pr --since "$B" --jobs 1 --verbose --json "$OUT/report.json" --html "$OUT/report.html" > "$OUT/replay-raw.log" 2>&1 || rc=$?
stamp "REPLAY_END exit=$rc" | tee -a "$L"
( for f in "coverage-$KEY.json" "inputs-$KEY.json" whole-suite-map-v2; do sha256sum ".saboteur/$f"; done ) > "$OUT/pointer-receipt-after.txt"
cmp <(sed 's/ .*//' "$OUT/pointer-receipt-before.txt") <(sed 's/ .*//' "$OUT/pointer-receipt-after.txt") && echo "SNAPSHOT_TRIPLE_UNCHANGED_AFTER_REPLAY key=$KEY pointer=$(tr -d '[:space:]' < .saboteur/whole-suite-map-v2)" | tee -a "$L" || { echo "SNAPSHOT_TRIPLE_CHANGED_DURING_REPLAY: report QUARANTINED, not qualified reuse" | tee -a "$L" "$OUT/QUARANTINED.txt"; exit 1; }
copy_cache_known replay | tee -a "$L"
[ -s "$OUT/report.json" ] || { echo "REPLAY_INCOMPLETE: no report.json (exit=$rc stopped_by=$(jq -r '.stopped_by // "none"' "$OUT/replay-meta.json"))" | tee -a "$L"; exit 1; }
jq -e . "$OUT/report.json" >/dev/null || { echo "REPLAY_INCOMPLETE: report.json is not valid JSON" | tee -a "$L"; exit 1; }
echo "REPORT_RECORDED bytes=$(wc -c < "$OUT/report.json") (existence is not qualification: scope, rejectedKills, test IDs and confirmation states are checked in review)" | tee -a "$L"
echo "REPLAY_EXIT=$rc (recorded raw; the report is evidence only after fresh triage, and confirmation evidence is bounded: initial executed IDs plus at most 8 pointer-covering IDs per survivor, 300s default budget; phase-specific executed IDs may be unavailable)" | tee -a "$L"
exit "$rc"
