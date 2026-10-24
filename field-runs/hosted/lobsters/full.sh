#!/usr/bin/env bash
# One job, fail closed: setup+control on BOTH trees, admission gate on the two native controls,
# then whole-suite map and replay on the head tree. Every stage writes receipts before it can fail.
set -uo pipefail
# JOB_T0 comes from the workflow, captured in its first step, so the budget covers checkout, packages and Ruby setup.
: "${JOB_T0:?}" "${JOB_MONO0:?}"
export JOB_T0 JOB_MONO0
: "${WS:?}" "${RECIPE_DIR:?}" "${TOOL_DIR:?}" "${PR:?}" "${OUT_ROOT:?}"
mkdir -p "$OUT_ROOT"; G="$OUT_ROOT/ADMISSION-GATE.txt"
gate_fail() { echo "ADMISSION_GATE=FAIL $*" | tee -a "$G"; exit 1; }
for SIDE in head base; do
  export SIDE APP_DIR="$WS/app-$SIDE" OUT="$OUT_ROOT/$SIDE"
  mkdir -p "$OUT"
  ( bash "$RECIPE_DIR/setup.sh" ) || gate_fail "setup failed on $SIDE"
  ( bash "$RECIPE_DIR/control.sh" ) || gate_fail "native control failed on $SIDE (raw preserved in $OUT)"
  n=$(jq -r '.summary.example_count' "$OUT/control-rspec.json"); f=$(jq -r '.summary.failure_count' "$OUT/control-rspec.json"); p=$(jq -r '.summary.pending_count' "$OUT/control-rspec.json")
  [[ "$n" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ && "$p" =~ ^[0-9]+$ ]] || gate_fail "$SIDE control JSON counts are not non-negative integers (n=$n f=$f p=$p)"
  echo "CONTROL $SIDE examples=$n failures=$f pending=$p (pending examples are counted in examples and disclosed, not treated as passes)" | tee -a "$G"
  [ "$f" -eq 0 ] && [ "$n" -gt 0 ] || gate_fail "$SIDE control not clean (examples=$n failures=$f)"
  if [ "$SIDE" = head ]; then N_head=$n; P_head=$p; else N_base=$n; P_base=$p; fi
done
echo "ADMISSION_GATE=PASS head_examples=$N_head (pending $P_head) base_examples=$N_base (pending $P_base) seed=3 (instrumented trees, fresh DB each; these are controls, not a qualification)" | tee -a "$G"
export SIDE=head APP_DIR="$WS/app-head" OUT="$OUT_ROOT/head"
( bash "$RECIPE_DIR/mr.sh" )
