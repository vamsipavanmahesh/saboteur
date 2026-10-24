# Shared helpers. Sourced by setup.sh, control.sh, mr.sh. Fail closed.
set -euo pipefail
: "${RECIPE_DIR:?}" "${APP_DIR:?}" "${TOOL_DIR:?}" "${PR:?}" "${SIDE:?}" "${OUT:?}"
SABOTEUR_PIN=6f87ccc98377bf0c23f3cf409006f0464c2aa67c
GEM_SHA256=16ef8af613ad2d1e010e08c585586807aaa2a33ac0f604d5828236981b63c9a1
SEED=3
export SABOTEUR_VERSION=0.12.3 SABOTEUR_SHA=$SABOTEUR_PIN RAILS_ENV=test
mkdir -p "$OUT"
stamp() { echo "$* realtime=$(date -Is) monotonic=$(cut -d' ' -f1 /proc/uptime)"; }
tree_sha() { awk -v p="$PR" -v s="$SIDE" '$1==p && $2==s {print $3}' "$RECIPE_DIR/trees.env"; }
base_sha() { awk -v p="$PR" '$1==p && $2=="base" {print $3}' "$RECIPE_DIR/trees.env"; }
# Every command that matters runs through measure3.py (owned child, receipts, normalized exit).
# measured <meta> <timeout_s> <cmd...>; the timeout never exceeds the job time left minus a reserve.
measured() { local meta=$1 to=$2; shift 2; local cap=$(( $(left_s) - 900 )); [ "$cap" -gt 60 ] || { echo "BUDGET_BLOCK: job time exhausted (left=$(left_s)s)"; return 97; }; [ "$to" -le "$cap" ] || to=$cap; python3 "$RECIPE_DIR/measure3.py" --meta "$meta" --cwd "$APP_DIR" --timeout "$to" -- "$@"; }
BUDGET_S=${BUDGET_S:-20400}
# Budget arithmetic is monotonic: JOB_MONO0 is /proc/uptime seconds captured by the workflow's first step.
: "${JOB_MONO0:?JOB_MONO0 must come from the workflow first step}"
left_s() { awk -v b="$BUDGET_S" -v t0="$JOB_MONO0" '{ printf "%d\n", b - ($1 - t0) }' /proc/uptime; }
# capped <max_seconds> <cmd...>: bound by the job time left; INT then KILL; exit 97 when the budget is gone.
capped() { local to=$1; shift; local cap=$(( $(left_s) - 900 )); [ "$cap" -gt 30 ] || { echo "BUDGET_BLOCK: job time exhausted (left=$(left_s)s)"; return 97; }; [ "$to" -le "$cap" ] || to=$cap; timeout --signal=INT --kill-after=30 "$to" "$@"; }
