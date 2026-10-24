# Shared helpers for the Human Essentials hosted recipe. Fail closed.
set -euo pipefail
: "${RECIPE_DIR:?}" "${TOOL_DIR:?}" "${OUT:?}" "${JOB_MONO0:?}"
SABOTEUR_PIN=6f87ccc98377bf0c23f3cf409006f0464c2aa67c
# One canonical absolute app root for EVERY job. Coverage keys are canonical absolute paths and are never rewritten.
APP_ROOT=/opt/he-app
BUDGET_S=${BUDGET_S:-20400}
export SABOTEUR_VERSION=0.12.3 SABOTEUR_SHA=$SABOTEUR_PIN RAILS_ENV=test BUNDLE_JOBS=1 MAKEFLAGS=-j1
export PG_HOST=${PG_HOST:-127.0.0.1} PG_USERNAME=${PG_USERNAME:-postgres} PG_PASSWORD=${PG_PASSWORD:-postgres}
mkdir -p "$OUT"
stamp() { echo "$* realtime=$(date -Is) monotonic=$(cut -d' ' -f1 /proc/uptime)"; }
left_s() { awk -v b="$BUDGET_S" -v t0="$JOB_MONO0" '{ printf "%d\n", b - ($1 - t0) }' /proc/uptime; }
capped() { local to=$1; shift; local cap=$(( $(left_s) - 900 )); [ "$cap" -gt 30 ] || { echo "BUDGET_BLOCK: job time exhausted (left=$(left_s)s)"; return 97; }; [ "$to" -le "$cap" ] || to=$cap; timeout --signal=INT --kill-after=30 "$to" "$@"; }
# measured <meta> <timeout_s> <cmd...>: owned process group, receipts, never longer than the job time left minus a reserve.
# A timeout is never shrunk silently: if the requested time does not fit, return 97 and do not start.
measured() { local meta=$1 to=$2; shift 2; local cap=$(( $(left_s) - 900 )); [ "$to" -le "$cap" ] || { echo "BUDGET_BLOCK: need ${to}s, have $cap"; return 97; }; python3 "$RECIPE_DIR/measure3.py" --meta "$meta" --cwd "$APP_ROOT" --timeout "$to" -- "$@"; }
row() { awk -v p="$1" '$1==p' "$RECIPE_DIR/eras.env"; }

# require_doctor: the doctor artifact of a verified run (DOC_ART_DIR) must be a green two-pass gate under the same recipe and identity.
require_doctor() {
  : "${DOC_ART_DIR:?}"
  python3 "$RECIPE_DIR/admit.py" compat "$DOC_ART_DIR" doctor "$OUT" "$(ruby -v)" || return 1
  echo "DOCTOR_ADMISSION_OK doctor_tree=$(grep -o 'tree [0-9a-f]\{40\}' "$DOC_ART_DIR/DOCTOR-VERDICT.txt")"
}

# The lock names the Bundler it was written with. Use exactly that version, never whatever the runner image ships.
if [ -f "$APP_ROOT/Gemfile.lock" ]; then
  BUNDLER_VERSION=$(tail -n1 "$APP_ROOT/Gemfile.lock" | tr -d ' ')
  [[ "$BUNDLER_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] && export BUNDLER_VERSION || unset BUNDLER_VERSION
fi

# copy_cache_known <label>: copy ONLY the known saboteur cache/evidence files (pin source: coverage_store, coverage_inputs_snapshot, baseline_guard,
# resume_manifest, engine results.json, crash_report) out of the hidden .saboteur root; any other name is NOT copied, only listed.
copy_cache_known() {
  local label=$1 dest="$OUT/$1-saboteur-dir" unk="$OUT/$1-saboteur-unknown.txt" rel n=0 known=0 listed=0
  mkdir -p "$dest"; : > "$unk"
  local pat='^(coverage-[0-9a-f]{64}\.json|inputs-[0-9a-f]{64}\.json|whole-suite-map-v2|coverage-[0-9a-f]{64}-part-[0-9]+-of-[0-9]+\.json|preview\.json|coverage-build\.log|coverage-build-[0-9]+\.log|internal-error\.log|results\.json|manifest\.json|report\.json|baseline-[0-9]+\.log|baseline-[0-9]+-part-[0-9]+\.log|logs/[A-Za-z0-9_.-]+\.log|baseline-evidence/[A-Za-z0-9_.-]+\.json)$'
  [ -d "$APP_ROOT/.saboteur" ] || { echo "CACHE_COPY $label no .saboteur directory"; return 0; }
  local lst; lst=$(mktemp); ( cd "$APP_ROOT/.saboteur" && find . -type f -print | sed 's#^\./##' | LC_ALL=C sort ) > "$lst"
  while IFS= read -r rel; do
    if [[ "$rel" =~ $pat ]]; then
      mkdir -p "$dest/$(dirname "$rel")"; cp -p "$APP_ROOT/.saboteur/$rel" "$dest/$rel"; known=$((known+1))
    else
      n=$((n+1))
      if [ "$n" -le 200 ]; then
        printf '%s %s\n' "$(printf '%s' "$rel" | sha256sum | cut -c1-16)" "$(printf '%s' "$rel" | LC_ALL=C head -c 120 | LC_ALL=C tr -c 'A-Za-z0-9._/-' '?')" >> "$unk"; listed=$((listed+1))
      fi
    fi
  done < "$lst"
  rm -f "$lst"
  echo "CACHE_COPY $label known_copied=$known unknown_total=$n unknown_listed=$listed unknown_truncated=$((n-listed)) (names sanitized: 16-hex digest of the raw name, 120-char truncation, non-[A-Za-z0-9._/-] replaced by ?, max 200 lines; unknown contents never copied)"
}
